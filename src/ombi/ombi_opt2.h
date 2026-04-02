/*
 * ombi_opt2.h — OMBI v2: Bitmap-Accelerated Bucket Queue with Caliber/F-set
 *
 * Improvements over ombi_opt.h (OMBI v1):
 *   1. Caliber optimization: precompute min incoming edge weight per vertex
 *      If dist(v) <= mu + caliber(v), v's distance is exact → push to F-stack
 *   2. F-set (stack): vertices with exact distances bypass buckets entirely,
 *      scanned with priority before any bucket extraction
 *   3. Cold PQ replaced with 4-ary heap for better cache locality
 *
 * Caliber theory (Goldberg et al.):
 *   caliber(v) = min { w(u,v) : (u,v) ∈ E }
 *   If dist(v) <= mu + caliber(v), then no future relaxation can improve v,
 *   because any path to v must use an edge of weight >= caliber(v), and
 *   mu is the minimum distance of any unsettled vertex.
 *
 * Based on: ombi_opt.h + Goldberg's caliber/F-set from smartq.cc
 */

#ifndef OMBI_OPT2_H
#define OMBI_OPT2_H

#include <cstdint>
#include <cstring>
#include <queue>
#include <vector>
#include <utility>
#include "../infrastructure/nodearc.h"

#define OMBI_VERY_FAR  9223372036854775807LL  /* LLONG_MAX */

#define OMBI_LIKELY(x)   __builtin_expect(!!(x), 1)
#define OMBI_UNLIKELY(x) __builtin_expect(!!(x), 0)

class OmbiQueue {
public:
    /* Configuration constants */
#ifndef OMBI_HOT_BUCKETS
#define OMBI_HOT_BUCKETS (1 << 14)
#endif
    static constexpr int HOT_BUCKETS = OMBI_HOT_BUCKETS;   /* default: 16384 */
    static constexpr int BMP_WORDS   = HOT_BUCKETS >> 6;
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

    /* Packed per-vertex state — 24 bytes */
    struct alignas(8) VState {
        long long dist;
        int distGen;
        int settledGen;
    };

    /* Constructor: allocate for graph with n nodes */
    OmbiQueue(int maxN);

    /* Destructor */
    ~OmbiQueue();

    /* Precompute calibers for the given graph (call once per graph) */
    void precomputeCalibers(const CsrGraph &g);

    /* Run SSSP from source on graph g. Returns number of nodes reached. */
    long sssp(const CsrGraph &g, int source);

    /* Get distance to node v after sssp(). Returns OMBI_VERY_FAR if unreached. */
    long long getDist(int v) const;

    /* Get the result array pointer */
    const long long* getDistArray() const { return result; }

    /* Statistics */
    long long getScans() const { return statScans; }
    long long getUpdates() const { return statUpdates; }
    long long getFsetSettled() const { return statFset; }

private:
    int n;

    /* Per-vertex state (packed) */
    VState *vs;
    int gen;

    /* Caliber array: min incoming edge weight per vertex */
    long long *caliber;
    bool calibersReady;

    /* F-set: stack of vertices with exact distances */
    int *fStack;
    int fTop;

    /* Hot zone: 16K circular buckets */
    BEntry **buckets;
    int *bCap;
    int *bCount;
    uint64_t *bmp;

    /* Cold zone: min-heap for overflow */
    using ColdEntry = std::pair<long long, int>;
    std::priority_queue<ColdEntry, std::vector<ColdEntry>,
                        std::greater<ColdEntry>> coldPQ;

    /* Result array */
    long long *result;
    int *touched;
    int touchedCount;
    int prevTouchedCount;
    bool resultInitialized;

    /* Statistics */
    long long statScans;
    long long statUpdates;
    long long statFset;     /* vertices settled via F-set */

    /* Internal methods */
    void extractFirstLive(int bi, int curGen,
                          int &hotCount, int &outU, long long &outDu);

    inline __attribute__((always_inline))
    void addToBucket(int bi, int v, long long d);

    int scanBitmapFirstLive(int trueCursor, int curGen,
                            int &hotCount, int &outU, long long &outDu,
                            int &lastBucketCirc);
};

#endif /* OMBI_OPT2_H */
