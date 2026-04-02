/*
 * dijkstra_radix1.cc — Dijkstra's SSSP with 1-Level Radix Heap
 *
 * Based on Ahuja, Mehlhorn, Orlin, Tarjan (1990):
 *   "Faster Algorithms for the Shortest Path Problem"
 *   Journal of the ACM, 37(2), pp. 213-223.
 *
 * A 1-level radix heap has K = 1 + ceil(log2(C+1)) buckets.
 * Bucket 0 holds vertices with dist == dMin (the current minimum).
 * Bucket i (for i >= 1) holds vertices with dist in range
 *   [dMin + 2^(i-1), dMin + 2^i - 1].
 *
 * ExtractMin: if bucket 0 is empty, find the smallest non-empty
 * bucket k, scan it to find the true minimum, then redistribute
 * all entries into lower buckets relative to the new minimum.
 *
 * Complexity: O(m + n * log C) — between binary heap and Dial.
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_r1 dijkstra_radix1.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_r1C dijkstra_radix1.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_r1 <graph.gr> <sources.ss> <output.txt>
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "../infrastructure/nodearc.h"

#define VERY_FAR  9223372036854775807LL
#define MODUL     ((long long) 1 << 62)

extern double timer();
extern int parse_gr(long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
                    long *node_min_ad, char *problem_name);
extern int parse_ss(long *sN_ad, long **source_array, char *aName);

/* ================================================================
 * 1-Level Radix Heap — Simple & Correct Implementation
 *
 * K buckets indexed 0..K-1 where K = 2 + floor(log2(C)).
 *
 * Bucket assignment for vertex v with distance d, given dMin:
 *   - If d == dMin: bucket 0
 *   - Else: bucket = msd(d XOR dMin) + 1
 *     where msd(x) = floor(log2(x)) = position of highest set bit
 *
 * This is the standard formulation from CLRS / Ahuja et al.
 * The XOR-based bucket assignment ensures that vertices whose
 * distances agree on the top bits go into the same (low) bucket.
 *
 * Key invariant: bucket i contains vertices with distances in
 * [dMin, dMin + 2^i - 1] that differ from dMin in bit position i-1
 * (or lower). Bucket 0 contains exactly those with dist == dMin.
 * ================================================================ */
struct RadixHeap1 {
    int n;
    long long *dist;
    bool *settled;

    int K;
    std::vector<int> *buckets;
    long long dMin;  /* current minimum distance */

    long long statScans;
    long long statUpdates;

    RadixHeap1(int maxN, long long maxW)
        : n(maxN), statScans(0), statUpdates(0)
    {
        dist    = new long long[n];
        settled = new bool[n];

        /* K = 2 + floor(log2(maxW)) for maxW >= 1
         * This gives enough buckets for any diff in [0, maxW]. */
        K = 2;
        long long v = maxW;
        while (v > 1) { v >>= 1; K++; }

        buckets = new std::vector<int>[K];
        dMin = 0;
    }

    ~RadixHeap1() {
        delete[] dist;
        delete[] settled;
        delete[] buckets;
    }

    /* Compute bucket index for distance d given current dMin.
     * Precondition: d >= dMin. */
    int bucketOf(long long d) const {
        if (d == dMin) return 0;
        /* msd(d XOR dMin) = floor(log2(d XOR dMin)) */
        long long x = d ^ dMin;
        int msb = 63 - __builtin_clzll(x);  /* floor(log2(x)) */
        int b = msb + 1;
        return (b < K) ? b : K - 1;
    }

    void sssp(const CsrGraph &g, int source) {
        statScans = 0;
        statUpdates = 0;

        for (int i = 0; i < n; i++) {
            dist[i] = VERY_FAR;
            settled[i] = false;
        }
        for (int i = 0; i < K; i++)
            buckets[i].clear();

        dist[source] = 0;
        dMin = 0;
        buckets[0].push_back(source);

        const int *__restrict__ offsets = g.offsets;
        const int *__restrict__ targets = g.targets;
        const long long *__restrict__ weights = g.weights;

        int settled_count = 0;

        while (settled_count < n) {
            /* Find first non-empty bucket */
            int k = 0;
            while (k < K && buckets[k].empty()) k++;
            if (k >= K) break;  /* all remaining vertices unreachable */

            if (k == 0) {
                /* Bucket 0: all entries have dist == dMin.
                 * Process them directly. */
                while (!buckets[0].empty()) {
                    int u = buckets[0].back();
                    buckets[0].pop_back();

                    if (settled[u]) continue;
                    if (dist[u] != dMin) continue;  /* stale */

                    settled[u] = true;
                    settled_count++;
                    statScans++;

                    long long du = dist[u];

                    const int eStart = offsets[u];
                    const int eEnd   = offsets[u + 1];
                    for (int e = eStart; e < eEnd; e++) {
                        const int v = targets[e];
                        if (settled[v]) continue;

                        const long long nd = du + weights[e];
                        if (nd < dist[v]) {
                            dist[v] = nd;
                            statUpdates++;
                            /* Insert into appropriate bucket.
                             * nd >= du = dMin, so bucketOf is valid. */
                            int b = bucketOf(nd);
                            buckets[b].push_back(v);
                        }
                    }
                }
            } else {
                /* Bucket k > 0: find true minimum, update dMin,
                 * redistribute all entries into lower buckets. */
                long long newMin = VERY_FAR;
                for (int v : buckets[k]) {
                    if (!settled[v] && dist[v] < newMin)
                        newMin = dist[v];
                }

                if (newMin == VERY_FAR) {
                    /* All stale — just clear */
                    buckets[k].clear();
                    continue;
                }

                dMin = newMin;

                /* Redistribute: take all entries from bucket k,
                 * recompute their bucket with the new dMin. */
                std::vector<int> temp;
                temp.swap(buckets[k]);

                for (int v : temp) {
                    if (settled[v]) continue;
                    if (dist[v] == VERY_FAR) continue;
                    int nb = bucketOf(dist[v]);
                    buckets[nb].push_back(v);
                }
                /* Loop back to find bucket 0 (which should now have entries) */
            }
        }
    }
};

/* ---------------------------------------------------------------- */
void ArcLen(long cNodes, Node *nodes,
            long long *pMin, long long *pMax)
{
    Arc *lastArc = (nodes + cNodes)->first - 1;
    long long maxLen = 0, minLen = VERY_FAR;
    for (Arc *arc = nodes->first; arc <= lastArc; arc++) {
        if (arc->len > maxLen) maxLen = arc->len;
        if (arc->len < minLen) minLen = arc->len;
    }
    if (pMin) *pMin = minLen;
    if (pMax) *pMax = maxLen;
}

int main(int argc, char **argv)
{
    double tm = 0.0;
    Arc *arcs;
    Node *nodes;
    long n, m, nmin, nQ;
    long *source_array = NULL;
    char gName[512], aName[512], oName[512];
    FILE *oFile;
    long long minArcLen, maxArcLen;

    if (argc != 4) {
        fprintf(stderr, "Usage: \"%s <graph> <aux> <out>\"\n", argv[0]);
        exit(1);
    }

    strcpy(gName, argv[1]);
    strcpy(aName, argv[2]);
    strcpy(oName, argv[3]);
    oFile = fopen(oName, "a");
    if (!oFile) { fprintf(stderr, "ERROR: cannot open %s\n", oName); exit(1); }

    fprintf(stderr, "c Dijkstra — 1-Level Radix Heap (Ahuja et al. 1990)\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;
    printf("p res ss dij_r1\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  MaxWeight: %lld  Trials: %ld\n",
            n, m, maxArcLen, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);
    RadixHeap1 solver(g.n, maxArcLen);

    fprintf(stderr, "c Radix buckets: %d (= 2 + floor(log2(maxWeight)))\n", solver.K);

    long long totalScans = 0, totalUpdates = 0;

    tm = timer();
    for (int i = 0; i < nQ; i++) {
        int source = (int)(source_array[i] - nmin);
        solver.sssp(g, source);

#ifdef CHECKSUM
        long long checksum = 0;
        for (int j = 0; j < g.n; j++) {
            if (solver.dist[j] < VERY_FAR)
                checksum = (checksum + (solver.dist[j] % MODUL)) % MODUL;
        }
        fprintf(oFile, "d %lld\n", checksum);
#endif

        totalScans   += solver.statScans;
        totalUpdates += solver.statUpdates;
    }
    tm = timer() - tm;
    (void)tm;

#ifndef CHECKSUM
    fprintf(stderr, "c Scans (ave): %.1f  Improvements (ave): %.1f\n",
            (double)totalScans / nQ, (double)totalUpdates / nQ);
    fprintf(stderr, "c Time (ave, ms): %.2f\n", 1000.0 * tm / nQ);

    fprintf(oFile, "g %ld %ld %lld %lld\n", n, m, minArcLen, maxArcLen);
    fprintf(oFile, "t %f\n", 1000.0 * tm / nQ);
    fprintf(oFile, "v %f\n", (double)totalScans / nQ);
    fprintf(oFile, "i %f\n", (double)totalUpdates / nQ);
#endif

    freeCsr(g);
    free(source_array);
    fclose(oFile);
    return 0;
}
