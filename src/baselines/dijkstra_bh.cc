/*
 * dijkstra_bh.cc — Dijkstra's SSSP with Binary Heap (std::priority_queue)
 *
 * Baseline comparison: standard lazy-deletion Dijkstra using C++ STL
 * binary min-heap. This is the universal baseline used in most SSSP
 * experimental studies (Cherkassky et al. 1996, Castro et al. 2025).
 *
 * Complexity: O((m + n) log n)
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_bh dijkstra_bh.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_bhC dijkstra_bh.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_bh <graph.gr> <sources.ss> <output.txt>
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <queue>
#include <vector>
#include <utility>
#include "../infrastructure/nodearc.h"

#define VERY_FAR  9223372036854775807LL
#define MODUL     ((long long) 1 << 62)

extern double timer();
extern int parse_gr(long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
                    long *node_min_ad, char *problem_name);
extern int parse_ss(long *sN_ad, long **source_array, char *aName);

/* ----------------------------------------------------------------
 * Binary Heap Dijkstra — lazy deletion
 * ---------------------------------------------------------------- */
struct BHSolver {
    int n;
    long long *dist;
    bool *settled;
    long long statScans;
    long long statUpdates;

    BHSolver(int maxN) : n(maxN), statScans(0), statUpdates(0) {
        dist    = new long long[n];
        settled = new bool[n];
    }

    ~BHSolver() {
        delete[] dist;
        delete[] settled;
    }

    void sssp(const CsrGraph &g, int source) {
        statScans = 0;
        statUpdates = 0;

        for (int i = 0; i < n; i++) {
            dist[i] = VERY_FAR;
            settled[i] = false;
        }

        using PQEntry = std::pair<long long, int>;
        std::priority_queue<PQEntry, std::vector<PQEntry>,
                            std::greater<PQEntry>> pq;

        dist[source] = 0;
        pq.push({0, source});

        const int *__restrict__ offsets = g.offsets;
        const int *__restrict__ targets = g.targets;
        const long long *__restrict__ weights = g.weights;

        while (!pq.empty()) {
            auto [du, u] = pq.top();
            pq.pop();

            if (settled[u]) continue;
            settled[u] = true;
            statScans++;

            /* Relax edges */
            const int eStart = offsets[u];
            const int eEnd   = offsets[u + 1];
            for (int e = eStart; e < eEnd; e++) {
                const int v = targets[e];
                if (settled[v]) continue;

                const long long nd = du + weights[e];
                if (nd < dist[v]) {
                    dist[v] = nd;
                    pq.push({nd, v});
                    statUpdates++;
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

    fprintf(stderr, "c Dijkstra — Binary Heap (std::priority_queue)\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;  /* used indirectly via nodes->first */
    printf("p res ss dij_bh\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  Trials: %ld\n", n, m, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);
    BHSolver solver(g.n);

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
    (void)tm;  /* suppress warning in CHECKSUM mode */

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
