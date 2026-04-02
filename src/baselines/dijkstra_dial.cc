/*
 * dijkstra_dial.cc — Dial's Algorithm (1-level bucket queue, bw=1)
 *
 * Dial's algorithm (1969) is the simplest bucket queue: one bucket per
 * integer distance value modulo numBuckets, where numBuckets = maxWeight + 1.
 * Linear scan for next non-empty bucket.
 *
 * Complexity: O(m + n*C) where C = max edge weight
 *
 * For road networks where C can be 200,000+, this means scanning
 * hundreds of thousands of empty buckets per extractMin. This
 * demonstrates WHY bitmap indexing (OMBI) and multi-level buckets
 * (Goldberg SQ) were invented.
 *
 * Implementation: circular array of size (maxWeight + 1) with
 * std::vector<int> per bucket. Key invariant: at any point during
 * Dijkstra, all tentative distances of unsettled vertices lie in
 * [d_min, d_min + C], so numBuckets = C + 1 guarantees no collisions.
 *
 * NOTE: We use vectors instead of intrusive linked lists to avoid a
 * subtle cycle bug: when a vertex's distance improves but maps to the
 * same bucket (dist_old % numBuckets == dist_new % numBuckets), an
 * intrusive linked list creates a cycle. Vectors + settled[] are safe.
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_dial dijkstra_dial.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_dialC dijkstra_dial.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_dial <graph.gr> <sources.ss> <output.txt>
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
 * Dial's Algorithm — circular bucket array, bucket width = 1
 *
 * Uses std::vector<int> per bucket. Circular buffer of size C+1.
 *
 * Key correctness points:
 * 1. numBuckets = C + 1 guarantees no distance collision.
 * 2. settled[] prevents re-processing.
 * 3. dist[v] check at extraction time catches stale entries.
 * 4. Vectors avoid the intrusive-linked-list cycle bug.
 * ================================================================ */
struct DialSolver {
    int n;
    long long *dist;
    bool *settled;

    long long numBuckets;
    std::vector<int> *buckets;

    long long statScans;
    long long statUpdates;

    DialSolver(int maxN, long long maxW)
        : n(maxN), statScans(0), statUpdates(0)
    {
        dist    = new long long[n];
        settled = new bool[n];

        numBuckets = maxW + 1;
        buckets = new std::vector<int>[numBuckets];
    }

    ~DialSolver() {
        delete[] dist;
        delete[] settled;
        delete[] buckets;
    }

    void sssp(const CsrGraph &g, int source) {
        statScans = 0;
        statUpdates = 0;

        for (int i = 0; i < n; i++) {
            dist[i] = VERY_FAR;
            settled[i] = false;
        }
        for (long long i = 0; i < numBuckets; i++)
            buckets[i].clear();

        dist[source] = 0;
        buckets[0].push_back(source);

        const int *__restrict__ offsets = g.offsets;
        const int *__restrict__ targets = g.targets;
        const long long *__restrict__ weights = g.weights;

        /* scanPos: monotonically advancing position in circular buffer.
         * We scan at most numBuckets positions before concluding all
         * remaining vertices are unreachable. */
        long long scanPos = 0;
        long long scannedEmpty = 0;  /* consecutive empty buckets scanned */

        while (scannedEmpty < numBuckets) {
            int idx = (int)(scanPos % numBuckets);

            /* Process all valid vertices in this bucket */
            bool found = false;
            while (!buckets[idx].empty()) {
                int u = buckets[idx].back();
                buckets[idx].pop_back();

                /* Skip stale: already settled or distance changed */
                if (settled[u]) continue;
                if (dist[u] % numBuckets != idx) continue;

                found = true;
                settled[u] = true;
                statScans++;

                long long du = dist[u];

                /* Relax outgoing edges */
                const int eStart = offsets[u];
                const int eEnd   = offsets[u + 1];
                for (int e = eStart; e < eEnd; e++) {
                    const int v = targets[e];
                    if (settled[v]) continue;

                    const long long nd = du + weights[e];
                    if (nd < dist[v]) {
                        dist[v] = nd;
                        statUpdates++;
                        int bv = (int)(nd % numBuckets);
                        buckets[bv].push_back(v);
                    }
                }
            }

            if (found) {
                scannedEmpty = 0;
            } else {
                scannedEmpty++;
            }
            scanPos++;
        }
    }
};

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

    fprintf(stderr, "c Dial's Algorithm — 1-level bucket queue (bw=1)\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;
    printf("p res ss dij_dial\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  MaxWeight: %lld  Trials: %ld\n",
            n, m, maxArcLen, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);
    DialSolver solver(g.n, maxArcLen);

    fprintf(stderr, "c Dial buckets: %lld (= maxWeight + 1)\n", solver.numBuckets);

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
