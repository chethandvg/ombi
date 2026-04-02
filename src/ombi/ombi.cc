/*
 * ombi.cc — Bitmap-Accelerated Bucket Queue SSSP (OMBI)
 *
 * OMBI: Ordered Minimum via Bitmap Indexing
 * Integer distances (long long) for DIMACS road networks.
 */

#include "ombi.h"
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
    dist       = new long long[n];
    distGen    = new int[n];
    settledGen = new int[n];
    touched    = new int[n];
    result     = new long long[n];

    /* Zero out generation arrays so gen=1 is always "new" */
    memset(distGen,    0, n * sizeof(int));
    memset(settledGen, 0, n * sizeof(int));

    /* Allocate bucket arrays */
    buckets = new BEntry*[HOT_BUCKETS];
    bCap    = new int[HOT_BUCKETS];
    bCount  = new int[HOT_BUCKETS];
    bmp     = new uint64_t[BMP_WORDS];

    for (int i = 0; i < HOT_BUCKETS; i++) {
        buckets[i] = new BEntry[4];  /* initial capacity 4 */
        bCap[i] = 4;
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
    delete[] dist;
    delete[] distGen;
    delete[] settledGen;
    delete[] touched;
    delete[] result;
}

/* ----------------------------------------------------------------
 * SSSP: Main Dijkstra loop with bitmap bucket queue
 * ---------------------------------------------------------------- */

long OmbiQueue::sssp(const CsrGraph &g, int source)
{
    gen++;
    int curGen = gen;

    /* Reset hot zone */
    memset(bCount, 0, HOT_BUCKETS * sizeof(int));
    memset(bmp,    0, BMP_WORDS * sizeof(uint64_t));

    /* Clear the cold PQ (swap with empty) */
    {
        std::priority_queue<ColdEntry, std::vector<ColdEntry>,
                            std::greater<ColdEntry>> empty;
        coldPQ.swap(empty);
    }

    /* Reset result array (lazy: only clear previously touched vertices) */
    if (!resultInitialized) {
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
    dist[source] = 0;
    distGen[source] = curGen;
    touched[touchedCount++] = source;

    /* Compute bucket width */
    long long minW = g.minWeight;
    if (minW < 1) minW = 1;
    long long bw = minW * BW_MULT;

    /* Seed bucket 0 with source */
    buckets[0][0].vert = source;
    buckets[0][0].dist = 0;
    bCount[0] = 1;
    bmp[0] |= 1ULL;
    int hotCount = 1;
    int trueCursor = 0;
    int lastBucketCirc = -1;

    /* Pointers for fast access */
    const int *offsets = g.offsets;
    const int *targets = g.targets;
    const long long *weights = g.weights;

    long nodesReached = 0;

    while (hotCount > 0 || !coldPQ.empty())
    {
        int u = -1;
        long long du = OMBI_VERY_FAR;

        /* --- Try to extract from hot zone --- */
        if (hotCount > 0)
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
            if (settledGen[cv] == curGen ||
                cd > (distGen[cv] == curGen ? dist[cv] : OMBI_VERY_FAR))
            {
                coldPQ.pop();
                continue;
            }

            long long coldDist = (distGen[cv] == curGen) ? dist[cv] : OMBI_VERY_FAR;

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
                    if (settledGen[pv] == curGen ||
                        pd > (distGen[pv] == curGen ? dist[pv] : OMBI_VERY_FAR))
                    {
                        coldPQ.pop();
                        continue;
                    }
                    long long pvDist = (distGen[pv] == curGen) ? dist[pv] : OMBI_VERY_FAR;
                    if (pvDist >= windowEnd) break;
                    coldPQ.pop();
                    int pvBi = (int)((pvDist / bw) & MASK);
                    addToBucket(pvBi, pv, pvDist);
                    hotCount++;
                }
            }
            break;
        }

        if (u < 0) break;

        /* --- Settle u --- */
        if (settledGen[u] == curGen) continue;
        settledGen[u] = curGen;
        nodesReached++;
        statScans++;

        long long windowEnd2 = (long long)(trueCursor + HOT_BUCKETS) * bw;
        int eStart = offsets[u];
        int eEnd   = offsets[u + 1];

        /* --- Relax edges --- */
        for (int e = eStart; e < eEnd; e++)
        {
            int v = targets[e];
            if (settledGen[v] == curGen) continue;

            long long nd = du + weights[e];
            long long vDist = (distGen[v] == curGen) ? dist[v] : OMBI_VERY_FAR;

            if (nd < vDist)
            {
                if (distGen[v] != curGen)
                    touched[touchedCount++] = v;

                dist[v] = nd;
                distGen[v] = curGen;
                statUpdates++;

                if (nd < windowEnd2)
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
        result[v] = dist[v];
    }
    prevTouchedCount = touchedCount;

    return nodesReached;
}

/* ----------------------------------------------------------------
 * getDist: return distance to vertex v
 * ---------------------------------------------------------------- */

long long OmbiQueue::getDist(int v) const
{
    return result[v];
}

/* ----------------------------------------------------------------
 * extractFirstLive: LIFO extraction from a specific bucket
 *
 * Pops entries from the end of bucket[bi] until we find one that
 * is still live (not settled, distance matches). Stale entries
 * are discarded (lazy deletion).
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

        /* Stale? (settled, or distance changed since insertion) */
        if (settledGen[v] == curGen || entry.dist != dist[v])
        {
            hotCount--;
            continue;
        }

        outU = v;
        outDu = dist[v];
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
 * addToBucket: insert entry into bucket bi (with dynamic resize)
 * ---------------------------------------------------------------- */

void OmbiQueue::addToBucket(int bi, int v, long long d)
{
    int cnt = bCount[bi];

    if (cnt >= bCap[bi])
    {
        int newCap = bCap[bi] * 2;
        BEntry *nb = new BEntry[newCap];
        memcpy(nb, buckets[bi], cnt * sizeof(BEntry));
        delete[] buckets[bi];
        buckets[bi] = nb;
        bCap[bi] = newCap;
    }

    BEntry &entry = buckets[bi][cnt];
    entry.vert = v;
    entry.dist = d;
    bCount[bi] = cnt + 1;
    bmp[bi >> 6] |= 1ULL << (bi & 63);
}

/* ----------------------------------------------------------------
 * scanBitmapFirstLive: scan bitmap starting from trueCursor
 *
 * Uses __builtin_ctzll() (compiles to TZCNT on x86) to skip
 * 64 empty buckets at once. This is the key performance advantage
 * over linear empty-bucket scanning.
 *
 * Returns the trueBi of the found bucket, or -1 if nothing found.
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

        /* Mask off bits before our starting position */
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

            word &= word - 1;  /* clear lowest set bit */
        }

        bitsRemaining -= (64 - bitOffset);
        trueOffset    += (64 - bitOffset);
        bitOffset = 0;
        wordIdx = (wordIdx + 1) & (BMP_WORDS - 1);
    }

done:
    return -1;
}
