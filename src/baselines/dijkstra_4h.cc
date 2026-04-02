/*
 * dijkstra_4h.cc — Dijkstra's SSSP with 4-ary Indexed Heap (cache-friendly)
 *
 * A d-ary heap with d=4 is widely regarded as the fastest comparison-based
 * priority queue for Dijkstra on modern hardware (LaMarca & Ladner 1996,
 * Cherkassky et al. 1996). The 4-ary tree has half the height of a binary
 * heap, and children of a node fit in one cache line (4 × 8 = 32 bytes).
 *
 * This uses an INDEXED 4-ary heap with decrease-key, which avoids the
 * lazy-deletion overhead of the binary heap baseline.
 *
 * Complexity: O((m + n) log_4 n) = O((m + n) log n / 2)
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_4h dijkstra_4h.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_4hC dijkstra_4h.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_4h <graph.gr> <sources.ss> <output.txt>
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "../infrastructure/nodearc.h"

#define VERY_FAR  9223372036854775807LL
#define MODUL     ((long long) 1 << 62)

extern double timer();
extern int parse_gr(long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
                    long *node_min_ad, char *problem_name);
extern int parse_ss(long *sN_ad, long **source_array, char *aName);

/* ================================================================
 * Indexed 4-ary Min-Heap
 *
 * heap[0..size-1]  : array of (dist, vertex) pairs
 * pos[v]           : index of vertex v in heap[], or -1 if not in heap
 *
 * Children of node at index i: 4*i+1, 4*i+2, 4*i+3, 4*i+4
 * Parent of node at index i:   (i-1)/4
 * ================================================================ */
struct Heap4 {
    struct Entry {
        long long dist;
        int vert;
    };

    Entry *heap;
    int *pos;     /* pos[vertex] = index in heap, -1 = not present */
    int size;
    int maxN;

    Heap4(int n) : maxN(n), size(0) {
        heap = new Entry[n];
        pos  = new int[n];
    }

    ~Heap4() {
        delete[] heap;
        delete[] pos;
    }

    void reset(int n) {
        size = 0;
        for (int i = 0; i < n; i++) pos[i] = -1;
    }

    bool empty() const { return size == 0; }

    void siftUp(int i) {
        Entry e = heap[i];
        while (i > 0) {
            int p = (i - 1) >> 2;   /* (i-1)/4 */
            if (heap[p].dist <= e.dist) break;
            heap[i] = heap[p];
            pos[heap[i].vert] = i;
            i = p;
        }
        heap[i] = e;
        pos[e.vert] = i;
    }

    void siftDown(int i) {
        Entry e = heap[i];
        while (true) {
            int child = (i << 2) + 1;   /* 4*i + 1 */
            if (child >= size) break;

            /* Find minimum among up to 4 children */
            int best = child;
            int end = child + 4;
            if (end > size) end = size;
            for (int c = child + 1; c < end; c++) {
                if (heap[c].dist < heap[best].dist)
                    best = c;
            }

            if (heap[best].dist >= e.dist) break;
            heap[i] = heap[best];
            pos[heap[i].vert] = i;
            i = best;
        }
        heap[i] = e;
        pos[e.vert] = i;
    }

    /* Insert vertex v with distance d. Assumes v not already in heap. */
    void insert(int v, long long d) {
        int i = size++;
        heap[i] = {d, v};
        pos[v] = i;
        siftUp(i);
    }

    /* Decrease key of vertex v to d. Assumes v is in heap and d < current. */
    void decreaseKey(int v, long long d) {
        int i = pos[v];
        heap[i].dist = d;
        siftUp(i);
    }

    /* Extract minimum. Returns {dist, vertex}. */
    Entry extractMin() {
        Entry top = heap[0];
        pos[top.vert] = -1;
        size--;
        if (size > 0) {
            heap[0] = heap[size];
            pos[heap[0].vert] = 0;
            siftDown(0);
        }
        return top;
    }

    bool contains(int v) const { return pos[v] >= 0; }
};

/* ----------------------------------------------------------------
 * 4-ary Heap Dijkstra — indexed with decrease-key
 *
 * Uses settled[] array to distinguish "never inserted" from
 * "already extracted" (both have pos[v] == -1 in the heap).
 * ---------------------------------------------------------------- */
struct FourHeapSolver {
    int n;
    long long *dist;
    bool *settled;
    Heap4 pq;
    long long statScans;
    long long statUpdates;

    FourHeapSolver(int maxN) : n(maxN), pq(maxN), statScans(0), statUpdates(0) {
        dist    = new long long[n];
        settled = new bool[n];
    }

    ~FourHeapSolver() {
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

        pq.reset(n);

        dist[source] = 0;
        pq.insert(source, 0);

        const int *__restrict__ offsets = g.offsets;
        const int *__restrict__ targets = g.targets;
        const long long *__restrict__ weights = g.weights;

        while (!pq.empty()) {
            auto [du, u] = pq.extractMin();
            settled[u] = true;
            statScans++;

            const int eStart = offsets[u];
            const int eEnd   = offsets[u + 1];
            for (int e = eStart; e < eEnd; e++) {
                const int v = targets[e];
                if (settled[v]) continue;

                const long long nd = du + weights[e];

                if (nd < dist[v]) {
                    bool wasInHeap = pq.contains(v);
                    dist[v] = nd;
                    statUpdates++;

                    if (wasInHeap) {
                        pq.decreaseKey(v, nd);
                    } else {
                        pq.insert(v, nd);
                    }
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

    fprintf(stderr, "c Dijkstra — 4-ary Indexed Heap\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;  /* used indirectly via nodes->first */
    printf("p res ss dij_4h\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  Trials: %ld\n", n, m, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);
    FourHeapSolver solver(g.n);

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
