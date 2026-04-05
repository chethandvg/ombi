/*
 * main.cc — DIMACS Challenge driver for OMBI Bitmap Bucket Queue SSSP
 *
 * Usage:
 *   ./ombi <graph.gr> <sources.ss> <output.txt>
 *   ./ombiC <graph.gr> <sources.ss> <output.txt>   (checksum mode)
 *
 * Output format matches Goldberg's sq/sqC for direct comparison:
 *   stderr: timing and statistics
 *   stdout: "p res ss ombi" header
 *   output file: "f <graph> <aux>\n" + "d <checksum>\n" per source
 *                + "g n m minW maxW\n" + "t <avg_ms>\n"
 *                + "v <avg_scans>\n" + "i <avg_updates>\n"
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o ombi main.cc ombi.cc \
 *       ../infrastructure/parser_gr.cc ../infrastructure/timer.cc \
 *       ../infrastructure/parser_ss.cc -lm
 *
 * Compile-time flags:
 *   -DOMBI_OPT     Use optimized variant (ombi_opt.h)
 *   -DOMBI_V2      Use caliber/F-set variant (ombi_opt2.h)
 *   -DCHECKSUM     Enable checksum output mode
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#if defined(OMBI_V3)
#include "ombi_v3.h"
#elif defined(OMBI_V2)
#include "ombi_opt2.h"
#elif defined(OMBI_OPT)
#include "ombi_opt.h"
#else
#include "ombi.h"
#endif

#define MODUL ((long long) 1 << 62)

/* External functions from Goldberg's code */
extern double timer();
extern int parse_gr(long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
                    long *node_min_ad, char *problem_name);
extern int parse_ss(long *sN_ad, long **source_array, char *aName);

/* Forward declaration */
void ArcLen(long cNodes, Node *nodes,
            long long *pMin, long long *pMax);

/* ArcLen: find min and max arc lengths (same as Goldberg's) */
void ArcLen(long cNodes, Node *nodes,
            long long *pMin, long long *pMax)
{
    Arc *lastArc, *arc;
    long long maxLen = 0, minLen = OMBI_VERY_FAR;

    lastArc = (nodes + cNodes)->first - 1;
    for (arc = nodes->first; arc <= lastArc; arc++) {
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
        fprintf(stderr,
                "Usage: \"%s <graph file> <aux file> <out file>\"\n",
                argv[0]);
        exit(1);
    }

    strcpy(gName, argv[1]);
    strcpy(aName, argv[2]);
    strcpy(oName, argv[3]);
    oFile = fopen(oName, "a");
    if (!oFile) {
        fprintf(stderr, "ERROR: cannot open output file %s\n", oName);
        exit(1);
    }

    fprintf(stderr, "c ---------------------------------------------------\n");
#if defined(OMBI_V3)
    fprintf(stderr, "c OMBI v3 (Two-Level Bitmap + Pool) — DIMACS Challenge format\n");
#elif defined(OMBI_V2)
    fprintf(stderr, "c OMBI v2 (Caliber/F-set) — DIMACS Challenge format\n");
#elif defined(OMBI_OPT)
    fprintf(stderr, "c OMBI Optimized — DIMACS Challenge format\n");
#else
    fprintf(stderr, "c OMBI Bitmap Bucket Queue — DIMACS Challenge format\n");
#endif
    fprintf(stderr, "c ---------------------------------------------------\n");

    /* Parse graph (reusing Goldberg's parser) */
    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);

    /* Parse sources */
    printf("p res ss ombi\n");
    parse_ss(&nQ, &source_array, aName);

    fprintf(oFile, "f %s %s\n", gName, aName);
    fprintf(stderr, "c\n");

    /* Get arc length range */
    ArcLen(n, nodes, &minArcLen, &maxArcLen);

    fprintf(stderr, "c Nodes: %24ld       Arcs: %22ld\n", n, m);
    fprintf(stderr, "c MinArcLen: %20lld       MaxArcLen: %17lld\n",
            minArcLen, maxArcLen);
    fprintf(stderr, "c BucketWidth: %18lld       (4 x MinArcLen)\n",
            minArcLen * OmbiQueue::BW_MULT);
    fprintf(stderr, "c HotBuckets: %19d       BitmapWords: %15d\n",
            OmbiQueue::HOT_BUCKETS, OmbiQueue::BMP_WORDS);
    fprintf(stderr, "c Trials: %23ld\n", nQ);

    /* Convert to CSR representation */
    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);

    /* Create OMBI solver */
    OmbiQueue ombi(g.n);

#ifdef OMBI_V2
    /* Precompute calibers for the graph (one-time O(m) pass) */
    ombi.precomputeCalibers(g);
    fprintf(stderr, "c Calibers precomputed\n");
#endif

    /* Accumulate statistics */
    long long totalScans = 0;
    long long totalUpdates = 0;

    /* Run all SSSP queries */
    tm = timer();

    for (int i = 0; i < nQ; i++) {
        int source = (int)(source_array[i] - nmin);  /* 1-based → 0-based */

        ombi.sssp(g, source);

#ifdef CHECKSUM
        /* Compute checksum: sum of all reachable distances mod 2^62 */
        long long checksum = 0;
        const long long *dArr = ombi.getDistArray();
        for (int j = 0; j < g.n; j++) {
            if (dArr[j] < OMBI_VERY_FAR) {
                checksum = (checksum + (dArr[j] % MODUL)) % MODUL;
            }
        }
        fprintf(oFile, "d %lld\n", checksum);
#endif

        totalScans   += ombi.getScans();
        totalUpdates += ombi.getUpdates();
    }

    tm = timer() - tm;

#ifndef CHECKSUM
    /* Print statistics (matching Goldberg's format) */
    fprintf(stderr, "c Scans (ave): %20.1f     Improvements (ave): %10.1f\n",
            (double)totalScans / (double)nQ,
            (double)totalUpdates / (double)nQ);
    fprintf(stderr, "c Time (ave, ms): %18.2f\n",
            1000.0 * tm / (double)nQ);

    fprintf(oFile, "g %ld %ld %lld %lld\n", n, m, minArcLen, maxArcLen);
    fprintf(oFile, "t %f\n", 1000.0 * tm / (double)nQ);
    fprintf(oFile, "v %f\n", (double)totalScans / (double)nQ);
    fprintf(oFile, "i %f\n", (double)totalUpdates / (double)nQ);
#endif

    /* Cleanup */
    freeCsr(g);
    free(source_array);
    fclose(oFile);

    return 0;
}
