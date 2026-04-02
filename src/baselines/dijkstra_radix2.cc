/*
 * dijkstra_radix2.cc — Dijkstra's SSSP with 2-Level Radix Heap
 *
 * Based on Cherkassky, Goldberg, Silverstein (1999):
 *   "Buckets, Heaps, Lists, and Monotone Priority Queues"
 *   SIAM J. Computing, 28(4).
 *
 * A 2-level bucket queue uses two levels of circular bucket arrays:
 *   Level 1 (fine): B₁ buckets, each of width 1.
 *     fine[d % B₁] holds vertices with distance exactly d.
 *   Level 2 (coarse): B₂ buckets, each covering B₁ consecutive distances.
 *     coarse[(d / B₁) % B₂] holds vertices with distance in that range.
 *
 * B₁ = ceil(sqrt(C+1)), B₂ = ceil((C+1) / B₁) + 1
 * Total buckets: B₁ + B₂ ≈ 2 * sqrt(C)
 *
 * Insert: O(1) — compute d % B₁ or (d / B₁) % B₂
 * ExtractMin: amortized O(sqrt(C)) — scan fine, or redistribute from coarse
 *
 * Complexity: O(m + n * sqrt(C))
 *
 * Key invariant: At any time, the fine buckets contain all vertices with
 * distance in [minDist, minDist + B₁ - 1] (i.e., the current "fine window").
 * Coarse buckets contain vertices with distance >= minDist + B₁.
 *
 * When fine buckets are exhausted, we advance to the next non-empty coarse
 * bucket, redistribute its contents into fine buckets, and continue.
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_r2 dijkstra_radix2.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_r2C dijkstra_radix2.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_r2 <graph.gr> <sources.ss> <output.txt>
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include "../infrastructure/nodearc.h"

#define VERY_FAR  9223372036854775807LL
#define MODUL     ((long long) 1 << 62)

extern double timer();
extern int parse_gr(long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
                    long *node_min_ad, char *problem_name);
extern int parse_ss(long *sN_ad, long **source_array, char *aName);

/* ================================================================
 * 2-Level Circular Bucket Queue
 *
 * Design:
 *   fine[d % B1]: vertices with distance exactly d
 *   coarse[(d / B1) % B2]: vertices with distance in a B1-wide range
 *
 *   On insert(v, d):
 *     if d < fineBase + B1:  fine[d % B1].push_back(v)
 *     else:                  coarse[(d / B1) % B2].push_back(v)
 *
 *   fineBase = start of current fine window (multiple of B1 in practice,
 *   but we track the exact minimum).
 *
 *   ExtractMin:
 *   1. Scan fine[scanPos % B1 .. ] for non-empty bucket with valid entry.
 *   2. If all B1 fine buckets empty, find next non-empty coarse bucket.
 *      Redistribute its contents into fine buckets. Update fineBase.
 *   3. Process vertex from fine bucket.
 *
 *   Stale detection: dist[v] != expected distance → skip.
 *   For fine: dist[v] should equal the distance corresponding to that bucket.
 *   For coarse: dist[v] may have been improved → skip if settled or if
 *     dist[v] < fineBase (already processed range).
 * ================================================================ */

struct RadixHeap2 {
    int n;
    long long *dist;
    bool *settled;

    int B1;                         /* number of fine buckets */
    int B2;                         /* number of coarse buckets */
    std::vector<int> *fine;         /* fine[0..B1-1]: vertex IDs */
    std::vector<int> *coarse;       /* coarse[0..B2-1]: vertex IDs */

    long long scanPos;              /* current scan position in fine array */

    long long statScans;
    long long statUpdates;

    RadixHeap2(int maxN, long long maxW)
        : n(maxN), statScans(0), statUpdates(0)
    {
        dist    = new long long[n];
        settled = new bool[n];

        B1 = (int)ceil(sqrt((double)(maxW + 1)));
        if (B1 < 2) B1 = 2;
        B2 = (int)((maxW + B1) / B1) + 1;
        if (B2 < 2) B2 = 2;

        fine   = new std::vector<int>[B1];
        coarse = new std::vector<int>[B2];
        scanPos = 0;
    }

    ~RadixHeap2() {
        delete[] dist;
        delete[] settled;
        delete[] fine;
        delete[] coarse;
    }

    /* Insert vertex v with distance d. */
    void insert(int v, long long d) {
        /* Fine window covers [scanPos, scanPos + B1 - 1].
         * But scanPos might be in the middle of a fine bucket range.
         * Actually, let's use a simpler model:
         *   fine window covers distances where (d / B1) == (scanPos / B1)
         *   i.e., the same "coarse group" as scanPos.
         * No — that's wrong too. Let's use the standard approach:
         *
         * Fine covers [fineBase, fineBase + B1 - 1] where fineBase = scanPos
         * rounded down... Actually, the simplest correct approach:
         *
         * A vertex with distance d goes to fine if it would map to the
         * same coarse bucket as the current minimum, or if d < fineBase + B1.
         * Otherwise it goes to coarse.
         *
         * Simplest: just use the coarse bucket index.
         * If (d / B1) == (scanPos / B1), it's in the current fine window → fine.
         * Otherwise → coarse.
         */
        long long dGroup = d / B1;
        long long sGroup = scanPos / B1;
        if (dGroup == sGroup) {
            fine[(int)(d % B1)].push_back(v);
        } else {
            coarse[(int)(dGroup % B2)].push_back(v);
        }
    }

    void sssp(const CsrGraph &g, int source) {
        statScans = 0;
        statUpdates = 0;

        for (int i = 0; i < n; i++) {
            dist[i] = VERY_FAR;
            settled[i] = false;
        }
        for (int i = 0; i < B1; i++) fine[i].clear();
        for (int i = 0; i < B2; i++) coarse[i].clear();

        dist[source] = 0;
        scanPos = 0;
        fine[0].push_back(source);

        const int *__restrict__ offs = g.offsets;
        const int *__restrict__ tgts = g.targets;
        const long long *__restrict__ wts = g.weights;

        int settled_count = 0;

        while (settled_count < n) {
            /* Step 1: Find next non-empty fine bucket */
            long long curGroup = scanPos / B1;
            long long groupEnd = (curGroup + 1) * B1;  /* first dist in next group */
            bool found = false;

            for (long long d = scanPos; d < groupEnd; d++) {
                int fi = (int)(d % B1);
                /* Drain stale */
                while (!fine[fi].empty()) {
                    int v = fine[fi].back();
                    if (settled[v] || dist[v] != d) {
                        fine[fi].pop_back();
                    } else {
                        break;
                    }
                }
                if (!fine[fi].empty()) {
                    scanPos = d;
                    found = true;
                    break;
                }
            }

            if (found) {
                int fi = (int)(scanPos % B1);
                long long curDist = scanPos;

                while (!fine[fi].empty()) {
                    int u = fine[fi].back();
                    fine[fi].pop_back();

                    if (settled[u]) continue;
                    if (dist[u] != curDist) continue;

                    settled[u] = true;
                    settled_count++;
                    statScans++;

                    long long du = dist[u];
                    const int eStart = offs[u];
                    const int eEnd   = offs[u + 1];
                    for (int e = eStart; e < eEnd; e++) {
                        const int v = tgts[e];
                        if (settled[v]) continue;
                        const long long nd = du + wts[e];
                        if (nd < dist[v]) {
                            dist[v] = nd;
                            statUpdates++;
                            insert(v, nd);
                        }
                    }
                }
                continue;
            }

            /* Step 2: All fine buckets in current group exhausted.
             * Find next non-empty coarse bucket and redistribute. */
            int startCi = (int)((curGroup + 1) % B2);
            int cb = -1;

            for (int k = 0; k < B2; k++) {
                int ci = (startCi + k) % B2;
                /* Drain stale */
                while (!coarse[ci].empty()) {
                    int v = coarse[ci].back();
                    if (settled[v] || dist[v] == VERY_FAR) {
                        coarse[ci].pop_back();
                    } else {
                        break;
                    }
                }
                if (!coarse[ci].empty()) {
                    cb = ci;
                    break;
                }
            }

            if (cb < 0) break;  /* all remaining vertices unreachable */

            /* Find true minimum distance in coarse[cb].
             * All entries here have (dist[v] / B1) % B2 == cb (at insertion time),
             * but some may be stale. We need the minimum dist[v] among non-stale. */
            long long newMin = VERY_FAR;
            for (int v : coarse[cb]) {
                if (!settled[v] && dist[v] < VERY_FAR && dist[v] < newMin) {
                    newMin = dist[v];
                }
            }

            if (newMin == VERY_FAR) {
                coarse[cb].clear();
                continue;
            }

            /* Set scanPos to newMin. Redistribute coarse[cb] into fine. */
            scanPos = newMin;
            long long newGroup = newMin / B1;

            /* Clear fine buckets */
            for (int i = 0; i < B1; i++) fine[i].clear();

            std::vector<int> temp;
            temp.swap(coarse[cb]);

            for (int v : temp) {
                if (settled[v] || dist[v] == VERY_FAR) continue;
                long long dv = dist[v];
                long long dvGroup = dv / B1;
                if (dvGroup == newGroup) {
                    fine[(int)(dv % B1)].push_back(v);
                } else {
                    /* Goes back to a (different) coarse bucket */
                    coarse[(int)(dvGroup % B2)].push_back(v);
                }
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

    fprintf(stderr, "c Dijkstra — 2-Level Radix Heap (Cherkassky et al. 1999)\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;
    printf("p res ss dij_r2\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  MaxWeight: %lld  Trials: %ld\n",
            n, m, maxArcLen, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);
    RadixHeap2 solver(g.n, maxArcLen);

    fprintf(stderr, "c Fine buckets (B1): %d  Coarse buckets (B2): %d  Total: %d\n",
            solver.B1, solver.B2, solver.B1 + solver.B2);

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
