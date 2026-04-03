/*
 * ombi_v3.cc — OMBI v3: Two-Level Bitmap Buckets + Pool Allocator
 *
 * Key changes from ombi_opt.cc (v1):
 *   1. Two-level buckets: L0 (16K fine, width=bw) + L1 (256 coarse, width=bw*16K)
 *      Insert: if nd < L0_end → L0; else if nd < L1_end → L1; else → cold PQ
 *      Extract: L0 bitmap scan → L1 redistribute into L0 → cold PQ (rare)
 *   2. Pool allocator: single BEntry[] with singly-linked freelist
 *      Eliminates 16K individual heap allocations + bCap[] tracking
 *   3. Compact VState: 16 bytes (uint16_t distGen + settledGen)
 *      Saves 8 bytes/vertex (191MB on 23.9M-node USA graph)
 */

#include "ombi_v3.h"
#include <cstdlib>
#include <cstring>
#include <cassert>
#include <algorithm>

/* ----------------------------------------------------------------
 * Pool allocator
 * ---------------------------------------------------------------- */

int OmbiQueue::poolAlloc()
{
    if (OMBI_UNLIKELY(freeHead < 0))
        poolGrow();

    int idx = freeHead;
    freeHead = pool[idx].next;
    return idx;
}

void OmbiQueue::poolFree(int idx)
{
    pool[idx].next = freeHead;
    freeHead = idx;
}

void OmbiQueue::poolGrow()
{
    int newSize = poolSize * 2;
    BEntry *newPool = new BEntry[newSize];
    memcpy(newPool, pool, poolSize * sizeof(BEntry));

    /* Fix existing bucket linked-list pointers — they're indices, so still valid */
    /* Only need to init freelist for new entries */
    for (int i = poolSize; i < newSize - 1; i++)
        newPool[i].next = i + 1;
    newPool[newSize - 1].next = freeHead;   /* chain old freelist at end */
    freeHead = poolSize;

    delete[] pool;
    pool = newPool;
    poolSize = newSize;
}

/* ----------------------------------------------------------------
 * Constructor / Destructor
 * ---------------------------------------------------------------- */

OmbiQueue::OmbiQueue(int maxN)
    : n(maxN), gen(0), touchedCount(0), prevTouchedCount(0),
      resultInitialized(false), statScans(0), statUpdates(0)
{
    /* Compact vertex state — single allocation, 16 bytes each */
    vs = new VState[n];
    memset(vs, 0, n * sizeof(VState));

    touched = new int[n];
    result  = new long long[n];

    /* Pool allocator: initial capacity = max(n, 2 * L0_BUCKETS)
     * Road networks typically have ~2-3× nodes in total bucket entries */
    poolSize = std::max(n, 2 * L0_BUCKETS);
    pool = new BEntry[poolSize];
    /* Initialize freelist */
    for (int i = 0; i < poolSize - 1; i++)
        pool[i].next = i + 1;
    pool[poolSize - 1].next = -1;
    freeHead = 0;

    /* L0: 16K fine-grained buckets */
    l0Head  = new int[L0_BUCKETS];
    l0Count = new int[L0_BUCKETS];
    l0Bmp   = new uint64_t[L0_BMP_WORDS];

    /* L1: 256 coarse-grained buckets */
    l1Head  = new int[L1_BUCKETS];
    l1Count = new int[L1_BUCKETS];
    l1Bmp   = new uint64_t[L1_BMP_WORDS];
}

OmbiQueue::~OmbiQueue()
{
    delete[] pool;
    delete[] l0Head;
    delete[] l0Count;
    delete[] l0Bmp;
    delete[] l1Head;
    delete[] l1Count;
    delete[] l1Bmp;
    delete[] vs;
    delete[] touched;
    delete[] result;
}

/* ----------------------------------------------------------------
 * resetGenerations — handle uint16_t overflow (every 65535 queries)
 * ---------------------------------------------------------------- */

void OmbiQueue::resetGenerations()
{
    memset(vs, 0, n * sizeof(VState));
    gen = 0;
}

/* ----------------------------------------------------------------
 * L0 operations
 * ---------------------------------------------------------------- */

void OmbiQueue::addToL0(int bi, int v, long long d)
{
    int idx = poolAlloc();
    pool[idx].vert = v;
    pool[idx].dist = d;
    pool[idx].next = l0Head[bi];
    l0Head[bi] = idx;
    l0Count[bi]++;
    l0Bmp[bi >> 6] |= 1ULL << (bi & 63);
}

void OmbiQueue::extractFirstLiveL0(int bi, uint16_t curGen,
                                    int &l0Total, int &outU, long long &outDu)
{
    outU = -1;
    outDu = OMBI_VERY_FAR;

    int prev = -1;
    int cur = l0Head[bi];

    while (cur >= 0)
    {
        int v = pool[cur].vert;

        /* Stale check: settled or distance changed */
        if (vs[v].settledGen == curGen || pool[cur].dist != vs[v].dist)
        {
            /* Remove stale entry from list */
            int next = pool[cur].next;
            if (prev < 0)
                l0Head[bi] = next;
            else
                pool[prev].next = next;
            l0Count[bi]--;
            l0Total--;
            poolFree(cur);
            cur = next;
            continue;
        }

        /* Found live entry — remove and return */
        outU = v;
        outDu = vs[v].dist;

        int next = pool[cur].next;
        if (prev < 0)
            l0Head[bi] = next;
        else
            pool[prev].next = next;
        l0Count[bi]--;
        l0Total--;
        poolFree(cur);

        if (l0Count[bi] == 0)
            l0Bmp[bi >> 6] &= ~(1ULL << (bi & 63));

        return;
    }

    /* Bucket exhausted (all stale) */
    l0Head[bi] = -1;
    l0Count[bi] = 0;
    l0Bmp[bi >> 6] &= ~(1ULL << (bi & 63));
}

int OmbiQueue::scanL0BitmapFirstLive(int trueCursor, uint16_t curGen,
                                      int &l0Total, int &outU, long long &outDu,
                                      int &lastBucketCirc)
{
    outU = -1;
    outDu = OMBI_VERY_FAR;
    lastBucketCirc = -1;

    int startCirc = trueCursor & L0_MASK;
    int startWord = startCirc >> 6;
    int startBit  = startCirc & 63;

    int bitsRemaining = L0_BUCKETS;
    int wordIdx   = startWord;
    int bitOffset = startBit;
    int trueOffset = 0;

    while (bitsRemaining > 0)
    {
        uint64_t word = l0Bmp[wordIdx];

        if (bitOffset > 0)
            word &= ~((1ULL << bitOffset) - 1);

        while (word != 0)
        {
            int bit = __builtin_ctzll(word);
            int circBi = (wordIdx << 6) | bit;
            int trueBi = trueCursor + trueOffset + (bit - bitOffset);

            if (trueBi >= trueCursor + L0_BUCKETS)
                goto done;

            extractFirstLiveL0(circBi, curGen, l0Total, outU, outDu);
            if (outU >= 0)
            {
                if (l0Count[circBi] > 0)
                    lastBucketCirc = circBi;
                return trueBi;
            }

            word &= word - 1;
        }

        bitsRemaining -= (64 - bitOffset);
        trueOffset    += (64 - bitOffset);
        bitOffset = 0;
        wordIdx = (wordIdx + 1) & (L0_BMP_WORDS - 1);
    }

done:
    return -1;
}

/* ----------------------------------------------------------------
 * L1 operations
 * ---------------------------------------------------------------- */

void OmbiQueue::addToL1(int bi, int v, long long d)
{
    int idx = poolAlloc();
    pool[idx].vert = v;
    pool[idx].dist = d;
    pool[idx].next = l1Head[bi];
    l1Head[bi] = idx;
    l1Count[bi]++;
    l1Bmp[bi >> 6] |= 1ULL << (bi & 63);
}

/*
 * redistributeL1ToL0 — Pull entries from L1 bucket l1Bi into L0 buckets.
 *
 * FIX: Only redistribute entries whose distance falls within the expected
 * logical L1 range [trueL1Bi * l1bw, (trueL1Bi+1) * l1bw). Entries from
 * other logical ranges (due to circular wrapping) are kept in the L1 bucket.
 * This prevents out-of-order extraction that violates Dijkstra's invariant.
 */
void OmbiQueue::redistributeL1ToL0(int l1Bi, long long bw, long long l1bw,
                                    int trueL1Bi, uint16_t curGen, int &l0Total)
{
    int cur = l1Head[l1Bi];
    int keepHead = -1;
    int keepCount = 0;

    const long long rangeStart = (long long)trueL1Bi * l1bw;
    const long long rangeEnd   = rangeStart + l1bw;

    while (cur >= 0)
    {
        int next = pool[cur].next;
        int v = pool[cur].vert;

        /* Discard stale */
        if (vs[v].settledGen == curGen || pool[cur].dist != vs[v].dist)
        {
            poolFree(cur);
            cur = next;
            continue;
        }

        long long d = pool[cur].dist;

        /* Only redistribute entries from the correct logical L1 range */
        if (d >= rangeStart && d < rangeEnd)
        {
            /* Redistribute to L0 */
            int bi = (int)((d / bw) & L0_MASK);

            pool[cur].next = l0Head[bi];
            l0Head[bi] = cur;
            l0Count[bi]++;
            l0Total++;
            l0Bmp[bi >> 6] |= 1ULL << (bi & 63);
        }
        else
        {
            /* Keep in L1 — belongs to a different logical range */
            pool[cur].next = keepHead;
            keepHead = cur;
            keepCount++;
        }

        cur = next;
    }

    if (keepCount > 0)
    {
        l1Head[l1Bi] = keepHead;
        l1Count[l1Bi] = keepCount;
        /* Bitmap bit stays set — bucket still has entries */
    }
    else
    {
        /* Clear L1 bucket */
        l1Head[l1Bi] = -1;
        l1Count[l1Bi] = 0;
        l1Bmp[l1Bi >> 6] &= ~(1ULL << (l1Bi & 63));
    }
}

/* ----------------------------------------------------------------
 * Helper: check if any L1 bitmap word is nonzero
 * ---------------------------------------------------------------- */
static inline bool l1_any_nonempty(const uint64_t *bmp)
{
    for (int i = 0; i < OmbiQueue::L1_BMP_WORDS; i++)
        if (bmp[i]) return true;
    return false;
}

/* ----------------------------------------------------------------
 * scanL1AndFillL0 — Scan L1 bitmap, redistribute entries to L0,
 * and extract a live vertex.
 *
 * FIX: Loops over ALL non-empty L1 buckets (not just one). If a bucket
 * produces only stale entries after redistribution, continues to the next.
 * Returns true if a live vertex was found.
 * ---------------------------------------------------------------- */
bool OmbiQueue::scanL1AndFillL0(int &trueCursor, int &l1Cursor,
                                long long bw, long long l1bw,
                                uint16_t curGen, int &l0Total,
                                int &outU, long long &outDu,
                                int &lastBucketCirc)
{
    outU = -1;
    outDu = OMBI_VERY_FAR;

    int startCirc = l1Cursor & L1_MASK;
    int startWord = startCirc >> 6;
    int startBit  = startCirc & 63;
    int bitsRem   = L1_BUCKETS;
    int wordIdx   = startWord;
    int bitOff    = startBit;
    int trueOff   = 0;

    while (bitsRem > 0)
    {
        uint64_t word = l1Bmp[wordIdx];
        if (bitOff > 0)
            word &= ~((1ULL << bitOff) - 1);

        while (word != 0)
        {
            int bit = __builtin_ctzll(word);
            int circBi = (wordIdx << 6) | bit;
            int trueL1Bi = l1Cursor + trueOff + (bit - bitOff);

            if (trueL1Bi >= l1Cursor + L1_BUCKETS)
                return false;   /* scanned all 256 positions */

            /* Set trueCursor to start of this L1 bucket's L0 range */
            trueCursor = trueL1Bi * L0_BUCKETS;
            lastBucketCirc = -1;

            /* Redistribute (with distance range check) */
            redistributeL1ToL0(circBi, bw, l1bw, trueL1Bi, curGen, l0Total);

            if (l0Total > 0)
            {
                int foundL0 = scanL0BitmapFirstLive(trueCursor, curGen,
                                                     l0Total, outU, outDu,
                                                     lastBucketCirc);
                if (foundL0 >= 0)
                {
                    trueCursor = foundL0;
                    l1Cursor = trueL1Bi + 1;
                    return true;
                }
            }

            /* All entries were stale — continue to next L1 bit */
            word &= word - 1;
        }

        bitsRem -= (64 - bitOff);
        trueOff += (64 - bitOff);
        bitOff = 0;
        wordIdx = (wordIdx + 1) & (L1_BMP_WORDS - 1);
    }

    return false;   /* L1 exhausted */
}

/* ----------------------------------------------------------------
 * insertThreeWay — Route a vertex to L0, L1, or cold PQ based on
 * its distance relative to the current window boundaries.
 * ---------------------------------------------------------------- */
void OmbiQueue::insertThreeWay(int v, long long d, long long bw,
                               long long l1bw, int trueCursor,
                               int l1Cursor, int &l0Total)
{
    const long long l0End = (long long)(trueCursor + L0_BUCKETS) * bw;
    const long long l1End = (long long)(l1Cursor + L1_BUCKETS) * l1bw;

    if (d < l0End)
    {
        int bi = (int)((d / bw) & L0_MASK);
        addToL0(bi, v, d);
        l0Total++;
    }
    else if (d < l1End)
    {
        int l1bi = (int)((d / l1bw) & L1_MASK);
        addToL1(l1bi, v, d);
    }
    else
    {
        coldPQ.push({d, v});
    }
}

/* ----------------------------------------------------------------
 * SSSP: Main Dijkstra loop with two-level bitmap bucket queue
 * ---------------------------------------------------------------- */

long OmbiQueue::sssp(const CsrGraph &g, int source)
{
    /* Handle generation overflow */
    if (OMBI_UNLIKELY(gen == 65535))
        resetGenerations();

    gen++;
    const uint16_t curGen = gen;

    /* Reset L0 */
    memset(l0Count, 0, L0_BUCKETS * sizeof(int));
    memset(l0Bmp,   0, L0_BMP_WORDS * sizeof(uint64_t));
    for (int i = 0; i < L0_BUCKETS; i++) l0Head[i] = -1;

    /* Reset L1 */
    memset(l1Count, 0, L1_BUCKETS * sizeof(int));
    memset(l1Bmp,   0, L1_BMP_WORDS * sizeof(uint64_t));
    for (int i = 0; i < L1_BUCKETS; i++) l1Head[i] = -1;

    /* Rebuild freelist — return all pool entries */
    for (int i = 0; i < poolSize - 1; i++)
        pool[i].next = i + 1;
    pool[poolSize - 1].next = -1;
    freeHead = 0;

    /* Clear cold PQ */
    while (!coldPQ.empty()) coldPQ.pop();

    /* Reset result array (lazy: only clear previously touched vertices) */
    if (OMBI_UNLIKELY(!resultInitialized)) {
        for (int i = 0; i < n; i++)
            result[i] = OMBI_VERY_FAR;
        resultInitialized = true;
    } else if (prevTouchedCount < (n >> 2)) {
        for (int i = 0; i < prevTouchedCount; i++)
            result[touched[i]] = OMBI_VERY_FAR;
    } else {
        for (int i = 0; i < n; i++)
            result[i] = OMBI_VERY_FAR;
    }

    touchedCount = 0;
    statScans = 0;
    statUpdates = 0;

    /* Initialize source */
    vs[source].dist = 0;
    vs[source].distGen = curGen;
    touched[touchedCount++] = source;

    /* Compute bucket width */
    long long minW = g.minWeight;
    if (minW < 1) minW = 1;
    const long long bw = minW * BW_MULT;

    /* L1 bucket width = bw * L0_BUCKETS */
    const long long l1bw = bw * L0_BUCKETS;

    /* Seed L0 bucket 0 with source */
    addToL0(0, source, 0);
    int l0Total = 1;
    int trueCursor = 0;
    int lastBucketCirc = -1;

    /* Window ends for insert-path decisions */
    /* These are updated whenever trueCursor changes */

    /* Cache CSR pointers */
    const int *__restrict__ offsets = g.offsets;
    const int *__restrict__ targets = g.targets;
    const long long *__restrict__ weights = g.weights;

    long nodesReached = 0;

    /* L1 cursor: tracks which L1 range we're currently serving */
    int l1Cursor = 0;

    while (l0Total > 0 || l1_any_nonempty(l1Bmp) || !coldPQ.empty())
    {
        int u = -1;
        long long du = OMBI_VERY_FAR;

        /* --- Step 1: Try to extract from L0 --- */
        if (OMBI_LIKELY(l0Total > 0))
        {
            /* Try the last bucket we found a live entry in */
            if (lastBucketCirc >= 0)
            {
                extractFirstLiveL0(lastBucketCirc, curGen, l0Total, u, du);
                if (u < 0) lastBucketCirc = -1;
            }

            /* Bitmap scan for next non-empty L0 bucket */
            if (u < 0 && l0Total > 0)
            {
                int found = scanL0BitmapFirstLive(trueCursor, curGen,
                                                   l0Total, u, du, lastBucketCirc);
                if (found >= 0)
                    trueCursor = found;
            }
        }

        /* --- Step 2: If L0 empty, try L1 (loops over stale buckets) --- */
        if (u < 0 && l1_any_nonempty(l1Bmp))
        {
            scanL1AndFillL0(trueCursor, l1Cursor, bw, l1bw,
                            curGen, l0Total, u, du, lastBucketCirc);
        }

        /* --- Step 3: Compare with cold PQ (ALWAYS, like v1) ---
         * This fixes the bug where cold PQ has a smaller distance
         * than the L1 result but was never checked. */
        while (!coldPQ.empty())
        {
            auto [cd, cv] = coldPQ.top();

            /* Skip stale cold entries */
            if (vs[cv].settledGen == curGen ||
                cd > (vs[cv].distGen == curGen ? vs[cv].dist : OMBI_VERY_FAR))
            {
                coldPQ.pop();
                continue;
            }

            long long coldDist = (vs[cv].distGen == curGen) ? vs[cv].dist : OMBI_VERY_FAR;

            if (u < 0 || coldDist < du)
            {
                /* Cold vertex wins — save old vertex for push-back */
                int oldU = u;
                long long oldDu = du;

                u = cv;
                du = coldDist;
                coldPQ.pop();
                trueCursor = (int)(du / bw);
                l1Cursor = (int)(du / l1bw);
                lastBucketCirc = -1;

                /* Push old vertex back directly to L0 (matching v1 behavior).
                 * When cold PQ wins, trueCursor jumps backward. The old vertex
                 * must go back to L0 at its circular position — not through
                 * insertThreeWay which might route it to L1/cold based on
                 * the new (smaller) cursor positions. */
                if (oldU >= 0)
                {
                    int pc = (int)((oldDu / bw) & L0_MASK);
                    addToL0(pc, oldU, oldDu);
                    l0Total++;
                }

                /* Drain cold PQ entries that now fit in L0 window.
                 * FIX: Only drain up to L0 window end, not L1 window end.
                 * Draining beyond L0 range into L0 circular buckets causes
                 * circular bucket collisions (same circular position, different
                 * logical position), violating Dijkstra's extraction order.
                 * Entries beyond L0 range stay in cold PQ (they'll be drained
                 * into L1 during future L1 redistribution). */
                const long long l0End_drain = (long long)(trueCursor + L0_BUCKETS) * bw;
                while (!coldPQ.empty())
                {
                    auto [pd, pv] = coldPQ.top();
                    if (vs[pv].settledGen == curGen ||
                        pd > (vs[pv].distGen == curGen ? vs[pv].dist : OMBI_VERY_FAR))
                    {
                        coldPQ.pop();
                        continue;
                    }
                    long long pvDist = (vs[pv].distGen == curGen) ? vs[pv].dist : OMBI_VERY_FAR;
                    if (pvDist >= l0End_drain) break;
                    coldPQ.pop();

                    int pvBi = (int)((pvDist / bw) & L0_MASK);
                    addToL0(pvBi, pv, pvDist);
                    l0Total++;
                }
            }
            break;
        }

        if (OMBI_UNLIKELY(u < 0)) break;

        /* --- Settle u --- */
        if (OMBI_UNLIKELY(vs[u].settledGen == curGen)) continue;
        vs[u].settledGen = curGen;
        nodesReached++;
        statScans++;

        /* Compute window boundaries for insert decisions */
        const long long l0End = (long long)(trueCursor + L0_BUCKETS) * bw;
        const long long l1End = (long long)(l1Cursor + L1_BUCKETS) * l1bw;
        const int eStart = offsets[u];
        const int eEnd   = offsets[u + 1];

        /* --- Relax edges --- */
        for (int e = eStart; e < eEnd; e++)
        {
            const int v = targets[e];
            if (OMBI_UNLIKELY(vs[v].settledGen == curGen)) continue;

            const long long nd = du + weights[e];
            const long long vDist = (vs[v].distGen == curGen) ? vs[v].dist : OMBI_VERY_FAR;

            if (nd < vDist)
            {
                if (vs[v].distGen != curGen)
                    touched[touchedCount++] = v;

                vs[v].dist = nd;
                vs[v].distGen = curGen;
                statUpdates++;

                /* Three-way insert: L0 (fast) → L1 + cold PQ backup → cold PQ */
                if (OMBI_LIKELY(nd < l0End))
                {
                    int bi = (int)((nd / bw) & L0_MASK);
                    addToL0(bi, v, nd);
                    l0Total++;
                }
                else if (nd < l1End)
                {
                    int l1bi = (int)((nd / l1bw) & L1_MASK);
                    addToL1(l1bi, v, nd);
                    /* Cold PQ backup: ensures correct Dijkstra ordering
                     * even if L1 redistribution timing is imperfect.
                     * The stale check discards whichever copy is processed
                     * second, so there is no double-processing. */
                    coldPQ.push({nd, v});
                }
                else
                {
                    coldPQ.push({nd, v});
                }
            }
        }
    }

    /* --- Copy results --- */
    for (int i = 0; i < touchedCount; i++)
    {
        int v = touched[i];
        result[v] = vs[v].dist;
    }
    prevTouchedCount = touchedCount;

    return nodesReached;
}

/* ----------------------------------------------------------------
 * getDist
 * ---------------------------------------------------------------- */

long long OmbiQueue::getDist(int v) const
{
    return result[v];
}
