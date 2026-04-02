/*
 * ombi_opt.h — Optimized OMBI: Bitmap-Accelerated Bucket Queue SSSP
 *
 * Optimizations over ombi.h:
 *   1. Packed vertex state struct (dist + distGen + settledGen in one cache line)
 *   2. Pool-allocated bucket entries (single large allocation, no per-bucket resize)
 *   3. Force-inlined addToBucket on the hot path
 *   4. Branch prediction hints (__builtin_expect)
 *   5. Eliminated std::priority_queue swap trick
 */

#ifndef OMBI_OPT_H
#define OMBI_OPT_H

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
    static constexpr int HOT_BUCKETS = 1 << 14;          /* 16384 */
    static constexpr int BMP_WORDS   = HOT_BUCKETS >> 6;  /* 256 */
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

    /* Packed per-vertex state — 24 bytes, fits 2.67 per cache line
     * Keeping dist/distGen/settledGen together improves locality
     * when checking "is this vertex settled?" + "what's its distance?" */
    struct alignas(8) VState {
        long long dist;
        int distGen;
        int settledGen;
    };

    /* Constructor: allocate for graph with n nodes */
    OmbiQueue(int maxN);

    /* Destructor */
    ~OmbiQueue();

    /* Run SSSP from source on graph g. Returns number of nodes reached. */
    long sssp(const CsrGraph &g, int source);

    /* Get distance to node v after sssp(). Returns OMBI_VERY_FAR if unreached. */
    long long getDist(int v) const;

    /* Get the result array pointer */
    const long long* getDistArray() const { return result; }

    /* Statistics */
    long long getScans() const { return statScans; }
    long long getUpdates() const { return statUpdates; }

private:
    int n;

    /* Per-vertex state (packed) */
    VState *vs;
    int gen;

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

    /* Internal methods */
    void extractFirstLive(int bi, int curGen,
                          int &hotCount, int &outU, long long &outDu);

    inline __attribute__((always_inline))
    void addToBucket(int bi, int v, long long d);

    int scanBitmapFirstLive(int trueCursor, int curGen,
                            int &hotCount, int &outU, long long &outDu,
                            int &lastBucketCirc);
};

#endif /* OMBI_OPT_H */
