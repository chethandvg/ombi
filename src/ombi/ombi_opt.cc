/*
 * ombi_opt.cc — Optimized OMBI: Bitmap-Accelerated Bucket Queue SSSP
 *
 * Optimizations over ombi.cc:
 *   1. Packed VState struct: dist + distGen + settledGen in 24 bytes
 *      → checking "settled?" and "current dist?" accesses same cache line
 *   2. Pre-sized bucket arrays: initial capacity 8 (road networks have
 *      moderate degree, reduces early resizes)
 *   3. Force-inlined addToBucket (hot path)
 *   4. Branch prediction hints for common cases
 *   5. Reuse cold PQ vector capacity across queries (no swap trick)
 */

#include "ombi_opt.h"
#include <cstdlib>
#include <cstring>
#include <cassert>

/* ----------------------------------------------------------------
 * Constructor / Destructor
 * ---------------------------------------------------------------- */

OmbiQueue::OmbiQueue(int maxN)
    : n(maxN), gen(0), touchedCount(0), prevTouchedCount(0),
      resultInitialized(false), statScans(0), statUpdates(0)
{
    /* Packed vertex state — single allocation */
    vs = new VState[n];
    memset(vs, 0, n * sizeof(VState));

    touched = new int[n];
    result  = new long long[n];

    /* Allocate bucket arrays with larger initial capacity (8 vs 4) */
    buckets = new BEntry*[HOT_BUCKETS];
    bCap    = new int[HOT_BUCKETS];
    bCount  = new int[HOT_BUCKETS];
    bmp     = new uint64_t[BMP_WORDS];

    for (int i = 0; i < HOT_BUCKETS; i++) {
        buckets[i] = new BEntry[8];   /* 8 initial (vs 4 in ombi.cc) */
        bCap[i] = 8;
    }
}

OmbiQueue::~OmbiQueue()
{
    for (int i = 0; i < HOT_BUCKETS; i++)
        delete[] buckets[i];
    delete[] buckets;
    delete[] bCap;
    delete[] bCount;
    delete[] bmp;
    delete[] vs;
    delete[] touched;
    delete[] result;
}

/* ----------------------------------------------------------------
 * SSSP: Main Dijkstra loop with bitmap bucket queue
 * ---------------------------------------------------------------- */

long OmbiQueue::sssp(const CsrGraph &g, int source)
{
    gen++;
    const int curGen = gen;

    /* Reset hot zone */
    memset(bCount, 0, HOT_BUCKETS * sizeof(int));
    memset(bmp,    0, BMP_WORDS * sizeof(uint64_t));

    /* Clear cold PQ — reuse vector capacity, just empty it */
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

    /* Seed bucket 0 with source */
    buckets[0][0] = {source, 0};
    bCount[0] = 1;
    bmp[0] |= 1ULL;
    int hotCount = 1;
    int trueCursor = 0;
    int lastBucketCirc = -1;

    /* Cache CSR pointers */
    const int *__restrict__ offsets = g.offsets;
    const int *__restrict__ targets = g.targets;
    const long long *__restrict__ weights = g.weights;

    long nodesReached = 0;

    while (hotCount > 0 || !coldPQ.empty())
    {
        int u = -1;
        long long du = OMBI_VERY_FAR;

        /* --- Try to extract from hot zone --- */
        if (OMBI_LIKELY(hotCount > 0))
        {
            /* First: try the last bucket we found a live entry in */
            if (lastBucketCirc >= 0)
            {
                extractFirstLive(lastBucketCirc, curGen, hotCount, u, du);
                if (u < 0) lastBucketCirc = -1;
            }

            /* Second: bitmap scan for next non-empty bucket */
            if (u < 0 && hotCount > 0)
            {
                int found = scanBitmapFirstLive(trueCursor, curGen,
                                                hotCount, u, du, lastBucketCirc);
                if (found >= 0)
                    trueCursor = found;
            }
        }

        /* --- Check cold PQ --- */
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
                /* Cold vertex wins — push hot vertex back if we had one */
                if (u >= 0)
                {
                    int pc = (int)((du / bw) & MASK);
                    addToBucket(pc, u, du);
                    hotCount++;
                }
                u = cv;
                du = coldDist;
                coldPQ.pop();
                trueCursor = (int)(du / bw);
                lastBucketCirc = -1;

                /* Drain cold PQ entries that fit in hot window */
                long long windowEnd = (long long)(trueCursor + HOT_BUCKETS) * bw;
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
                    if (pvDist >= windowEnd) break;
                    coldPQ.pop();
                    int pvBi = (int)((pvDist / bw) & MASK);
                    addToBucket(pvBi, pv, pvDist);
                    hotCount++;
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

        const long long windowEnd2 = (long long)(trueCursor + HOT_BUCKETS) * bw;
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

                if (OMBI_LIKELY(nd < windowEnd2))
                {
                    int bi = (int)((nd / bw) & MASK);
                    addToBucket(bi, v, nd);
                    hotCount++;
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

/* ----------------------------------------------------------------
 * extractFirstLive
 * ---------------------------------------------------------------- */

void OmbiQueue::extractFirstLive(int bi, int curGen,
                                 int &hotCount, int &outU, long long &outDu)
{
    outU = -1;
    outDu = OMBI_VERY_FAR;

    int cnt = bCount[bi];
    BEntry *bucket = buckets[bi];

    while (cnt > 0)
    {
        cnt--;
        BEntry &entry = bucket[cnt];
        int v = entry.vert;

        /* Stale? — packed struct: settledGen and dist are adjacent */
        if (vs[v].settledGen == curGen || entry.dist != vs[v].dist)
        {
            hotCount--;
            continue;
        }

        outU = v;
        outDu = vs[v].dist;
        bCount[bi] = cnt;
        hotCount--;

        if (cnt == 0)
            bmp[bi >> 6] &= ~(1ULL << (bi & 63));

        return;
    }

    /* Bucket exhausted (all stale) */
    bCount[bi] = 0;
    bmp[bi >> 6] &= ~(1ULL << (bi & 63));
}

/* ----------------------------------------------------------------
 * addToBucket (force-inlined)
 * ---------------------------------------------------------------- */

void OmbiQueue::addToBucket(int bi, int v, long long d)
{
    int cnt = bCount[bi];

    if (OMBI_UNLIKELY(cnt >= bCap[bi]))
    {
        int newCap = bCap[bi] * 2;
        BEntry *nb = new BEntry[newCap];
        memcpy(nb, buckets[bi], cnt * sizeof(BEntry));
        delete[] buckets[bi];
        buckets[bi] = nb;
        bCap[bi] = newCap;
    }

    buckets[bi][cnt] = {v, d};
    bCount[bi] = cnt + 1;
    bmp[bi >> 6] |= 1ULL << (bi & 63);
}

/* ----------------------------------------------------------------
 * scanBitmapFirstLive
 * ---------------------------------------------------------------- */

int OmbiQueue::scanBitmapFirstLive(int trueCursor, int curGen,
                                   int &hotCount, int &outU, long long &outDu,
                                   int &lastBucketCirc)
{
    outU = -1;
    outDu = OMBI_VERY_FAR;
    lastBucketCirc = -1;

    int startCirc = trueCursor & MASK;
    int startWord = startCirc >> 6;
    int startBit  = startCirc & 63;

    int bitsRemaining = HOT_BUCKETS;
    int wordIdx   = startWord;
    int bitOffset = startBit;
    int trueOffset = 0;

    while (bitsRemaining > 0)
    {
        uint64_t word = bmp[wordIdx];

        if (bitOffset > 0)
            word &= ~((1ULL << bitOffset) - 1);

        while (word != 0)
        {
            int bit = __builtin_ctzll(word);
            int circBi = (wordIdx << 6) | bit;
            int trueBi = trueCursor + trueOffset + (bit - bitOffset);

            if (trueBi >= trueCursor + HOT_BUCKETS)
                goto done;

            extractFirstLive(circBi, curGen, hotCount, outU, outDu);
            if (outU >= 0)
            {
                if (bCount[circBi] > 0)
                    lastBucketCirc = circBi;
                return trueBi;
            }

            word &= word - 1;
        }

        bitsRemaining -= (64 - bitOffset);
        trueOffset    += (64 - bitOffset);
        bitOffset = 0;
        wordIdx = (wordIdx + 1) & (BMP_WORDS - 1);
    }

done:
    return -1;
}
