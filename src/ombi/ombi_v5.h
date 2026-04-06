/*
 * ombi_v5.h — OMBI v5: Correctness-Fixed Two-Level Bitmap Buckets
 *
 * Based on OMBI v3 (Two-Level Bitmap + Pool Allocator), with a critical
 * correctness fix for low-C grids where bw > minWeight violates the
 * Dinitz bound.
 *
 * TWO STRATEGIES (compile-time selection):
 *
 *   v5 (default, -DOMBI_V5):
 *     Adaptive bucket width: when minWeight < BW_MULT, automatically
 *     falls back to bw = minWeight (≤ 1). This guarantees Dinitz
 *     correctness (no same-bucket insertions possible) at the cost of
 *     narrower buckets on low-C graphs. Road networks are unaffected
 *     because their minWeight is typically >> BW_MULT.
 *
 *   v5s (-DOMBI_V5S):
 *     Sorted-insert variant: inserts into L0 buckets in ascending
 *     distance order (sorted linked list). Extraction always yields the
 *     true minimum within a bucket, guaranteeing correctness even when
 *     bw > minWeight. Cost: O(k) per insert where k = bucket occupancy.
 *     On road networks (k ≈ 1-3), this is essentially free.
 *
 * Architecture (same as v3):
 *   ┌─────────────────────┐     ┌─────────────────────┐     ┌──────────┐
 *   │ L0: 16K fine buckets│ ──→ │ L1: 256 coarse bkts │ ──→ │ Tiny cold│
 *   │ Bitmap: 256 words   │     │ Bitmap: 4 words      │     │ PQ (rare)│
 *   │ Width: bw            │     │ Width: bw × 16K      │     └──────────┘
 *   │ Range: 16K × bw      │     │ Range: 256 × 16K × bw│
 *   └─────────────────────┘     └─────────────────────┘
 */

#ifndef OMBI_V5_H
#define OMBI_V5_H

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
    /* ---- L0 configuration (fine-grained) ---- */
#ifndef OMBI_HOT_BUCKETS
#define OMBI_HOT_BUCKETS (1 << 14)
#endif
    static constexpr int L0_BUCKETS  = OMBI_HOT_BUCKETS;   /* 16384 */
    static constexpr int L0_BMP_WORDS = L0_BUCKETS >> 6;    /* 256 */
    static constexpr int L0_MASK     = L0_BUCKETS - 1;

    /* ---- L1 configuration (coarse-grained) ---- */
    static constexpr int L1_BUCKETS   = 256;
    static constexpr int L1_BMP_WORDS = L1_BUCKETS >> 6;    /* 4 */
    static constexpr int L1_MASK      = L1_BUCKETS - 1;

    /* expose for main.cc diagnostics */
    static constexpr int HOT_BUCKETS = L0_BUCKETS;
    static constexpr int BMP_WORDS   = L0_BMP_WORDS;

#ifndef OMBI_BW_MULT
#define OMBI_BW_MULT 4
#endif
    static constexpr int BW_MULT     = OMBI_BW_MULT;

    /* Pool-allocated bucket entry: vertex + distance + freelist link */
    struct BEntry {
        int vert;
        long long dist;
        int next;           /* next entry in same bucket, or -1 */
    };

    /* Compact per-vertex state — 16 bytes (was 24 in v1)
     * Uses uint16_t generation fields; overflow at 65535 triggers full reset */
    struct alignas(8) VState {
        long long dist;         /* 8 bytes */
        uint16_t distGen;       /* 2 bytes */
        uint16_t settledGen;    /* 2 bytes */
        uint32_t _pad;          /* 4 bytes padding for alignment */
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

    /* Per-vertex state (compact) */
    VState *vs;
    uint16_t gen;

    /* ---- Pool allocator for bucket entries ---- */
    BEntry *pool;           /* single contiguous array */
    int poolSize;           /* total capacity */
    int freeHead;           /* head of freelist (-1 = empty) */

    int poolAlloc();        /* grab one entry from freelist */
    void poolFree(int idx); /* return entry to freelist */
    void poolGrow();        /* double pool capacity (rare) */

    /* ---- L0: Fine-grained buckets (16K circular) ---- */
    int *l0Head;            /* l0Head[i] = index of first BEntry, or -1 */
    int *l0Count;           /* count of entries per bucket */
    uint64_t *l0Bmp;        /* bitmap: 256 words */

    /* ---- L1: Coarse-grained buckets (256 circular) ---- */
    int *l1Head;            /* l1Head[i] = index of first BEntry, or -1 */
    int *l1Count;           /* count of entries per bucket */
    uint64_t *l1Bmp;        /* bitmap: 4 words */

    /* ---- Residual cold PQ (extremely rare overflow) ---- */
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

    /* L0 operations */
    inline __attribute__((always_inline))
    void addToL0(int bi, int v, long long d);

    void extractFirstLiveL0(int bi, uint16_t curGen,
                            int &l0Count_total, int &outU, long long &outDu);

    int scanL0BitmapFirstLive(int trueCursor, uint16_t curGen,
                              int &l0Count_total, int &outU, long long &outDu,
                              int &lastBucketCirc);

    /* L1 operations */
    inline __attribute__((always_inline))
    void addToL1(int bi, int v, long long d);

    void redistributeL1ToL0(int l1Bi, long long bw, long long l1bw,
                            int trueL1Bi, uint16_t curGen, int &l0Count_total);

    bool scanL1AndFillL0(int &trueCursor, int &l1Cursor, long long bw,
                         long long l1bw, uint16_t curGen, int &l0Total,
                         int &outU, long long &outDu, int &lastBucketCirc);

    /* Three-way insert: route to L0, L1, or cold PQ based on distance */
    void insertThreeWay(int v, long long d, long long bw, long long l1bw,
                        int trueCursor, int l1Cursor, int &l0Total);

    /* Generation overflow reset */
    void resetGenerations();
};

#endif /* OMBI_V5_H */
