/*
 * nodearc.h — Node/Arc definitions and CSR graph for OMBI DIMACS solver
 *
 * We reuse Goldberg's parser_gr.cc which expects his Node/Arc structs.
 * After parsing, we convert to CSR (offsets/targets/weights arrays).
 *
 * This header provides Goldberg-compatible structs for the parser,
 * plus our own CSR representation for the OMBI algorithm.
 */

#ifndef NODEARC_H
#define NODEARC_H

#include <cstdint>

/* ----------------------------------------------------------------
 * Goldberg-compatible structs (needed by parser_gr.cc)
 * These mirror his nodearc.h but without SQ-specific fields.
 * ---------------------------------------------------------------- */

#define IN_NONE       0
#define IN_HEAP       1
#define IN_F          2
#define IN_BUCKETS    4
#define IN_SCANNED    5

typedef struct Node;

typedef struct Arc {
    long long len;           /* arc length */
    struct Node *head;       /* destination node */
} Arc;

typedef struct Node {
    long long dist;          /* tentative distance */
    Arc *first;              /* first outgoing arc */
    struct Node *parent;     /* parent pointer (unused by OMBI, needed by parser) */
    char where;              /* data structure membership */
    unsigned int tStamp;     /* timestamp */

    /* Goldberg's bucket info — we don't use it, but parser_gr.cc
       may reference Node size, so keep struct layout compatible */
    struct {
        struct Node *next;
        struct Node *prev;
        void *bucket;
    } sBckInfo;
} Node;


/* ----------------------------------------------------------------
 * CSR Graph representation (used by OMBI algorithm)
 * ---------------------------------------------------------------- */

struct CsrGraph {
    int n;                   /* number of nodes */
    long m;                  /* number of arcs */
    int *offsets;            /* offsets[0..n], offsets[i] = first arc of node i */
    int *targets;            /* targets[0..m-1] = destination of arc j */
    long long *weights;      /* weights[0..m-1] = weight of arc j */
    long long minWeight;     /* minimum arc weight */
    long long maxWeight;     /* maximum arc weight */
};

/*
 * Convert Goldberg's adjacency-list representation to CSR.
 * nodes[0..n-1] with arcs stored contiguously.
 * Caller must free the CsrGraph arrays.
 */
static CsrGraph buildCsr(long n, Node *nodes, long m,
                          long long minW, long long maxW)
{
    CsrGraph g;
    g.n = (int)n;
    g.m = m;
    g.minWeight = minW;
    g.maxWeight = maxW;

    g.offsets = new int[n + 1];
    g.targets = new int[m];
    g.weights = new long long[m];

    int idx = 0;
    for (long i = 0; i < n; i++) {
        g.offsets[i] = idx;
        Arc *lastArc = (nodes + i + 1)->first - 1;
        for (Arc *a = (nodes + i)->first; a <= lastArc; a++) {
            g.targets[idx] = (int)(a->head - nodes);
            g.weights[idx] = a->len;
            idx++;
        }
    }
    g.offsets[n] = idx;

    return g;
}

static void freeCsr(CsrGraph &g) {
    delete[] g.offsets;
    delete[] g.targets;
    delete[] g.weights;
}

#endif /* NODEARC_H */
