/*
 * dijkstra_fh.cc — Dijkstra's SSSP with Fibonacci Heap
 *
 * Fibonacci heap gives the theoretically optimal O(m + n log n) for Dijkstra.
 * In practice it's slower than binary heaps due to pointer chasing, poor
 * cache locality, and high constant factors (Cherkassky et al. 1996).
 *
 * Included for completeness — this is the "theoretically optimal" baseline
 * that every SSSP paper references.
 *
 * Implementation: simplified Fibonacci heap with:
 *   - insert:       O(1) amortized
 *   - decrease-key: O(1) amortized
 *   - extract-min:  O(log n) amortized
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_fh dijkstra_fh.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_fhC dijkstra_fh.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_fh <graph.gr> <sources.ss> <output.txt>
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include "../infrastructure/nodearc.h"

#define VERY_FAR  9223372036854775807LL
#define MODUL     ((long long) 1 << 62)

extern double timer();
extern int parse_gr(long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
                    long *node_min_ad, char *problem_name);
extern int parse_ss(long *sN_ad, long **source_array, char *aName);

/* ================================================================
 * Fibonacci Heap
 *
 * Each node has: key, vertex, degree, mark, parent, child, left, right
 * Root list is a circular doubly-linked list.
 * ================================================================ */
struct FibNode {
    long long key;
    int vert;
    int degree;
    bool mark;
    FibNode *parent;
    FibNode *child;
    FibNode *left;
    FibNode *right;
};

struct FibHeap {
    FibNode *minNode;
    int count;
    FibNode *nodePool;   /* pre-allocated pool indexed by vertex */
    FibNode **degTable;  /* consolidation table */
    int maxDeg;

    FibHeap(int n) : minNode(nullptr), count(0) {
        nodePool = new FibNode[n];
        maxDeg = (int)(2.0 * log2((double)n + 1.0)) + 2;
        degTable = new FibNode*[maxDeg + 1];
    }

    ~FibHeap() {
        delete[] nodePool;
        delete[] degTable;
    }

    void reset() {
        minNode = nullptr;
        count = 0;
    }

    /* Insert vertex v with key k. Returns the node. */
    FibNode* insert(int v, long long k) {
        FibNode *x = &nodePool[v];
        x->key = k;
        x->vert = v;
        x->degree = 0;
        x->mark = false;
        x->parent = nullptr;
        x->child = nullptr;

        if (minNode == nullptr) {
            x->left = x;
            x->right = x;
            minNode = x;
        } else {
            /* Insert into root list */
            x->left = minNode;
            x->right = minNode->right;
            minNode->right->left = x;
            minNode->right = x;
            if (k < minNode->key)
                minNode = x;
        }
        count++;
        return x;
    }

    bool empty() const { return minNode == nullptr; }

    /* Extract minimum node */
    FibNode* extractMin() {
        FibNode *z = minNode;
        if (z == nullptr) return nullptr;

        /* Add all children of z to root list */
        FibNode *child = z->child;
        if (child != nullptr) {
            FibNode *c = child;
            do {
                FibNode *next = c->right;
                /* Add c to root list */
                c->left = minNode;
                c->right = minNode->right;
                minNode->right->left = c;
                minNode->right = c;
                c->parent = nullptr;
                c = next;
            } while (c != child);
        }

        /* Remove z from root list */
        z->left->right = z->right;
        z->right->left = z->left;

        if (z == z->right) {
            minNode = nullptr;
        } else {
            minNode = z->right;
            consolidate();
        }

        count--;
        return z;
    }

    /* Decrease key of node x to k */
    void decreaseKey(FibNode *x, long long k) {
        x->key = k;
        FibNode *y = x->parent;
        if (y != nullptr && x->key < y->key) {
            cut(x, y);
            cascadingCut(y);
        }
        if (x->key < minNode->key)
            minNode = x;
    }

private:
    void consolidate() {
        for (int i = 0; i <= maxDeg; i++)
            degTable[i] = nullptr;

        /* Collect all roots first to avoid modifying list while iterating */
        int rootCount = 0;
        FibNode *x = minNode;
        if (x != nullptr) {
            rootCount++;
            x = x->right;
            while (x != minNode) {
                rootCount++;
                x = x->right;
            }
        }

        /* Process each root */
        FibNode *w = minNode;
        for (int i = 0; i < rootCount; i++) {
            x = w;
            w = w->right;
            int d = x->degree;

            while (d <= maxDeg && degTable[d] != nullptr) {
                FibNode *y = degTable[d];
                if (x->key > y->key) {
                    FibNode *tmp = x; x = y; y = tmp;
                }
                link(y, x);
                degTable[d] = nullptr;
                d++;
            }
            if (d <= maxDeg)
                degTable[d] = x;
        }

        /* Rebuild root list and find new min */
        minNode = nullptr;
        for (int i = 0; i <= maxDeg; i++) {
            if (degTable[i] != nullptr) {
                FibNode *node = degTable[i];
                if (minNode == nullptr) {
                    node->left = node;
                    node->right = node;
                    minNode = node;
                } else {
                    node->left = minNode;
                    node->right = minNode->right;
                    minNode->right->left = node;
                    minNode->right = node;
                    if (node->key < minNode->key)
                        minNode = node;
                }
            }
        }
    }

    void link(FibNode *y, FibNode *x) {
        /* Remove y from root list */
        y->left->right = y->right;
        y->right->left = y->left;

        /* Make y a child of x */
        y->parent = x;
        if (x->child == nullptr) {
            x->child = y;
            y->left = y;
            y->right = y;
        } else {
            y->left = x->child;
            y->right = x->child->right;
            x->child->right->left = y;
            x->child->right = y;
        }
        x->degree++;
        y->mark = false;
    }

    void cut(FibNode *x, FibNode *y) {
        /* Remove x from child list of y */
        if (x->right == x) {
            y->child = nullptr;
        } else {
            if (y->child == x)
                y->child = x->right;
            x->left->right = x->right;
            x->right->left = x->left;
        }
        y->degree--;

        /* Add x to root list */
        x->left = minNode;
        x->right = minNode->right;
        minNode->right->left = x;
        minNode->right = x;
        x->parent = nullptr;
        x->mark = false;
    }

    void cascadingCut(FibNode *y) {
        FibNode *z = y->parent;
        if (z != nullptr) {
            if (!y->mark) {
                y->mark = true;
            } else {
                cut(y, z);
                cascadingCut(z);
            }
        }
    }
};

/* ----------------------------------------------------------------
 * Fibonacci Heap Dijkstra — indexed with decrease-key
 * ---------------------------------------------------------------- */
struct FibSolver {
    int n;
    long long *dist;
    bool *settled;
    bool *inHeap;
    FibHeap fh;
    long long statScans;
    long long statUpdates;

    FibSolver(int maxN) : n(maxN), fh(maxN), statScans(0), statUpdates(0) {
        dist    = new long long[n];
        settled = new bool[n];
        inHeap  = new bool[n];
    }

    ~FibSolver() {
        delete[] dist;
        delete[] settled;
        delete[] inHeap;
    }

    void sssp(const CsrGraph &g, int source) {
        statScans = 0;
        statUpdates = 0;

        for (int i = 0; i < n; i++) {
            dist[i] = VERY_FAR;
            settled[i] = false;
            inHeap[i] = false;
        }

        fh.reset();

        dist[source] = 0;
        fh.insert(source, 0);
        inHeap[source] = true;

        const int *__restrict__ offsets = g.offsets;
        const int *__restrict__ targets = g.targets;
        const long long *__restrict__ weights = g.weights;

        while (!fh.empty()) {
            FibNode *zNode = fh.extractMin();
            int u = zNode->vert;
            long long du = zNode->key;
            settled[u] = true;
            inHeap[u] = false;
            statScans++;

            const int eStart = offsets[u];
            const int eEnd   = offsets[u + 1];
            for (int e = eStart; e < eEnd; e++) {
                const int v = targets[e];
                if (settled[v]) continue;

                const long long nd = du + weights[e];

                if (nd < dist[v]) {
                    dist[v] = nd;
                    statUpdates++;

                    if (inHeap[v]) {
                        fh.decreaseKey(&fh.nodePool[v], nd);
                    } else {
                        fh.insert(v, nd);
                        inHeap[v] = true;
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

    fprintf(stderr, "c Dijkstra — Fibonacci Heap\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;  /* used indirectly via nodes->first */
    printf("p res ss dij_fh\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  Trials: %ld\n", n, m, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);
    FibSolver solver(g.n);

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
