/*
 * dijkstra_ph.cc — Dijkstra's SSSP with Pairing Heap
 *
 * Pairing heaps are often the fastest pointer-based heap in practice
 * (Stasko & Vitter 1987, Moret & Shapiro 1991). They have:
 *   - insert:       O(1)
 *   - decrease-key: O(log log n) amortized (conjectured O(1))
 *   - extract-min:  O(log n) amortized
 *
 * Simpler than Fibonacci heaps (no cascading cuts, no degree tracking)
 * and typically faster due to better constants and cache behavior.
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_ph dijkstra_ph.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_phC dijkstra_ph.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_ph <graph.gr> <sources.ss> <output.txt>
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
 * Pairing Heap (min-heap)
 *
 * Each node has: key, vertex, child (leftmost child), sibling (next sibling)
 * Parent pointer for decrease-key.
 *
 * Uses two-pass pairing for extract-min (left-to-right pair, then
 * right-to-left merge).
 * ================================================================ */
struct PairNode {
    long long key;
    int vert;
    PairNode *child;     /* leftmost child */
    PairNode *sibling;   /* next sibling */
    PairNode *parent;    /* parent (for decrease-key cut) */
};

struct PairingHeap {
    PairNode *root;
    int count;
    PairNode *nodePool;
    PairNode **auxBuf;   /* buffer for two-pass pairing */
    int maxN;

    PairingHeap(int n) : root(nullptr), count(0), maxN(n) {
        nodePool = new PairNode[n];
        auxBuf   = new PairNode*[n + 1];
    }

    ~PairingHeap() {
        delete[] nodePool;
        delete[] auxBuf;
    }

    void reset() {
        root = nullptr;
        count = 0;
    }

    bool empty() const { return root == nullptr; }

    /* Merge two heaps — link the one with larger key under the smaller */
    PairNode* merge(PairNode *a, PairNode *b) {
        if (a == nullptr) return b;
        if (b == nullptr) return a;
        if (a->key > b->key) {
            PairNode *tmp = a; a = b; b = tmp;
        }
        /* b becomes leftmost child of a */
        b->sibling = a->child;
        b->parent = a;
        a->child = b;
        a->sibling = nullptr;
        a->parent = nullptr;
        return a;
    }

    /* Insert vertex v with key k */
    PairNode* insert(int v, long long k) {
        PairNode *x = &nodePool[v];
        x->key = k;
        x->vert = v;
        x->child = nullptr;
        x->sibling = nullptr;
        x->parent = nullptr;

        root = merge(root, x);
        count++;
        return x;
    }

    /* Extract minimum — two-pass pairing of children */
    PairNode* extractMin() {
        PairNode *oldRoot = root;
        if (root == nullptr) return nullptr;

        /* Collect children into auxBuf */
        int nChildren = 0;
        PairNode *c = root->child;
        while (c != nullptr) {
            auxBuf[nChildren++] = c;
            PairNode *next = c->sibling;
            c->sibling = nullptr;
            c->parent = nullptr;
            c = next;
        }

        if (nChildren == 0) {
            root = nullptr;
        } else {
            /* Left-to-right pairing pass */
            int i;
            for (i = 0; i + 1 < nChildren; i += 2) {
                auxBuf[i] = merge(auxBuf[i], auxBuf[i + 1]);
            }
            /* If odd number, last one stays */
            int last = (nChildren & 1) ? nChildren - 1 : nChildren - 2;

            /* Right-to-left accumulation pass */
            PairNode *acc = auxBuf[last];
            for (int j = last - 2; j >= 0; j -= 2) {
                acc = merge(auxBuf[j], acc);
            }
            root = acc;
        }

        count--;
        return oldRoot;
    }

    /* Decrease key of node x to k */
    void decreaseKey(PairNode *x, long long k) {
        x->key = k;

        if (x == root) return;  /* already root */

        /* Cut x from parent */
        PairNode *p = x->parent;
        if (p != nullptr) {
            if (p->child == x) {
                p->child = x->sibling;
            } else {
                /* Find x among siblings */
                PairNode *s = p->child;
                while (s != nullptr && s->sibling != x)
                    s = s->sibling;
                if (s != nullptr)
                    s->sibling = x->sibling;
            }
        } else {
            /* x might be a sibling of someone — need to find and unlink
             * This is the tricky case. With parent pointers, we handle it. */
            /* Actually if parent is null and x != root, x shouldn't exist
             * in the heap. This shouldn't happen with correct usage. */
        }

        x->parent = nullptr;
        x->sibling = nullptr;
        root = merge(root, x);
    }
};

/* ----------------------------------------------------------------
 * Pairing Heap Dijkstra — indexed with decrease-key
 * ---------------------------------------------------------------- */
struct PairingSolver {
    int n;
    long long *dist;
    bool *settled;
    bool *inHeap;
    PairingHeap ph;
    long long statScans;
    long long statUpdates;

    PairingSolver(int maxN) : n(maxN), ph(maxN), statScans(0), statUpdates(0) {
        dist    = new long long[n];
        settled = new bool[n];
        inHeap  = new bool[n];
    }

    ~PairingSolver() {
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

        ph.reset();

        dist[source] = 0;
        ph.insert(source, 0);
        inHeap[source] = true;

        const int *__restrict__ offsets = g.offsets;
        const int *__restrict__ targets = g.targets;
        const long long *__restrict__ weights = g.weights;

        while (!ph.empty()) {
            PairNode *zNode = ph.extractMin();
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
                        ph.decreaseKey(&ph.nodePool[v], nd);
                    } else {
                        ph.insert(v, nd);
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

    fprintf(stderr, "c Dijkstra — Pairing Heap\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;  /* used indirectly via nodes->first */
    printf("p res ss dij_ph\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  Trials: %ld\n", n, m, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);
    PairingSolver solver(g.n);

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
