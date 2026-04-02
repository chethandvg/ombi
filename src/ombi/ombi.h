/*
 * ombi.h — Bitmap-Accelerated Bucket Queue SSSP (OMBI)
 *
 * OMBI: Ordered Minimum via Bitmap Indexing
 *
 * Key innovations over Goldberg's Smart Queue:
 *   1. Wider bucket width: bw = 4 × minArcLen (vs ~minArcLen)
 *   2. Bitmap scan: __builtin_ctzll() skips 64 empty buckets at once
 *   3. AoS dynamic arrays in buckets (vs doubly-linked lists)
 *   4. Single-level hot zone + std::priority_queue cold overflow
 *   5. Generation-counter lazy initialization (O(1) per query)
 *
 * Correctness guarantee:
 *   For integer-weight graphs with bw = 4 × minWeight, LIFO extraction
 *   from buckets produces exact SSSP. Within a bucket, distances differ
 *   by at most 3. LIFO may process d+3 before d, but by the time we
 *   leave the bucket, all vertices are correctly relaxed.
 */

#ifndef OMBI_H
#define OMBI_H

#include <cstdint>
#include <cstring>
#include <queue>
#include <vector>
#include <utility>
#include "../infrastructure/nodearc.h"

#define OMBI_VERY_FAR  9223372036854775807LL  /* LLONG_MAX */

class OmbiQueue {
public:
    /* Configuration constants */
    static constexpr int HOT_BUCKETS = 1 << 14;        /* 16384 */
    static constexpr int BMP_WORDS   = HOT_BUCKETS >> 6; /* 256 */
    static constexpr int MASK        = HOT_BUCKETS - 1;
#ifndef OMBI_BW_MULT
#define OMBI_BW_MULT 4
#endif
    static constexpr int BW_MULT     = OMBI_BW_MULT;

    /* Bucket entry: vertex + distance snapshot */
    struct BEntry {
        int vert;
        long long dist;
    };

    /* Constructor: allocate for graph with n nodes */
    OmbiQueue(int maxN);

    /* Destructor */
    ~OmbiQueue();

    /* Run SSSP from source on graph g. Returns number of nodes reached. */
    long sssp(const CsrGraph &g, int source);

    /* Get distance to node v after sssp(). Returns OMBI_VERY_FAR if unreached. */
    long long getDist(int v) const;

    /* Get the result array pointer (valid until next sssp call) */
    const long long* getDistArray() const { return result; }

    /* Statistics */
    long long getScans() const { return statScans; }
    long long getUpdates() const { return statUpdates; }

private:
    int n;

    /* Per-vertex state (generation-based lazy init) */
    long long *dist;       /* tentative distance */
    int *distGen;          /* generation when dist was set */
    int *settledGen;       /* generation when vertex was settled */
    int gen;               /* current generation counter */

    /* Hot zone: 16K circular buckets */
    BEntry **buckets;      /* buckets[i] = dynamic array of entries */
    int *bCap;             /* capacity of each bucket array */
    int *bCount;           /* current count in each bucket */
    uint64_t *bmp;         /* bitmap: 1 bit per bucket (non-empty) */

    /* Cold zone: min-heap for overflow */
    using ColdEntry = std::pair<long long, int>;  /* (dist, vertex) */
    std::priority_queue<ColdEntry, std::vector<ColdEntry>,
                        std::greater<ColdEntry>> coldPQ;

    /* Result array */
    long long *result;
    int *touched;          /* list of touched vertices */
    int touchedCount;
    int prevTouchedCount;
    bool resultInitialized;

    /* Statistics */
    long long statScans;
    long long statUpdates;

    /* Internal methods */
    void extractFirstLive(int bi, int curGen,
                          int &hotCount, int &outU, long long &outDu);

    void addToBucket(int bi, int v, long long d);

    int scanBitmapFirstLive(int trueCursor, int curGen,
                            int &hotCount, int &outU, long long &outDu,
                            int &lastBucketCirc);
};

#endif /* OMBI_H */
