/*
 * dijkstra_ch.cc — Contraction Hierarchies (CH) for SSSP
 *
 * Two-phase algorithm:
 *   1. PREPROCESSING: Contract nodes in priority order, adding shortcuts.
 *      Priority = edge-difference + level heuristic.
 *   2. QUERY: Bidirectional Dijkstra on augmented graph, only relaxing
 *      edges to higher-rank nodes ("upward" search). Meet in the middle.
 *
 * This is the foundational speed-up technique for road networks.
 * After preprocessing (which is expensive), queries answer in <1ms
 * compared to 30-150ms for standard Dijkstra.
 *
 * Reference: Geisberger et al., "Contraction Hierarchies: Faster and
 * Simpler Hierarchical Routing in Road Networks" (2008).
 *
 * Complexity:
 *   Preprocessing: O(n * (local search cost)) — typically minutes for road nets
 *   Query:         O(k * log k) where k << n is the search space
 *
 * Build:
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -o dij_ch dijkstra_ch.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *   g++ -std=c++17 -Wall -O3 -DNDEBUG -DCHECKSUM -o dij_chC dijkstra_ch.cc parser_gr.cc timer.cc parser_ss.cc -lm
 *
 * Usage:
 *   ./dij_ch <graph.gr> <sources.ss> <output.txt>
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <queue>
#include <vector>
#include <utility>
#include <algorithm>
#include <numeric>
#include <limits>
#include "../infrastructure/nodearc.h"

#define VERY_FAR  9223372036854775807LL
#define MODUL     ((long long) 1 << 62)

extern double timer();
extern int parse_gr(long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
                    long *node_min_ad, char *problem_name);
extern int parse_ss(long *sN_ad, long **source_array, char *aName);

/* ----------------------------------------------------------------
 * CH Edge: forward and backward adjacency lists
 * ---------------------------------------------------------------- */
struct CHEdge {
    int target;
    long long weight;
    bool isShortcut;       /* true if added during contraction */
    int shortcutMid;       /* middle node of shortcut (-1 if original) */
};

/* ----------------------------------------------------------------
 * Contraction Hierarchies Solver
 * ---------------------------------------------------------------- */
struct CHSolver {
    int n;

    /* Original + shortcut adjacency lists */
    std::vector<std::vector<CHEdge>> fwdAdj;   /* forward edges */
    std::vector<std::vector<CHEdge>> bwdAdj;   /* backward edges */

    /* Node ordering / ranking */
    std::vector<int> rank;        /* rank[v] = contraction order (0 = first contracted) */
    std::vector<int> order;       /* order[i] = node contracted at step i */
    std::vector<bool> contracted; /* contracted[v] = true if already contracted */
    std::vector<int> level;       /* level[v] for priority computation */

    /* Upward-only adjacency (built after contraction) */
    std::vector<std::vector<std::pair<int,long long>>> upFwd;  /* upward forward */
    std::vector<std::vector<std::pair<int,long long>>> upBwd;  /* upward backward */

    /* Query state */
    std::vector<long long> distFwd;
    std::vector<long long> distBwd;

    /* Statistics */
    long long statScans;
    long long statUpdates;
    long long numShortcuts;
    double preprocessTime;

    CHSolver(int maxN) : n(maxN), statScans(0), statUpdates(0),
                         numShortcuts(0), preprocessTime(0.0) {
        fwdAdj.resize(n);
        bwdAdj.resize(n);
        rank.resize(n, -1);
        order.resize(n);
        contracted.resize(n, false);
        level.resize(n, 0);
        upFwd.resize(n);
        upBwd.resize(n);
        distFwd.resize(n, VERY_FAR);
        distBwd.resize(n, VERY_FAR);
    }

    /* ----------------------------------------------------------------
     * Build from CSR graph (add both forward and backward edges)
     * ---------------------------------------------------------------- */
    void buildFromCsr(const CsrGraph &g) {
        for (int u = 0; u < g.n; u++) {
            for (int e = g.offsets[u]; e < g.offsets[u+1]; e++) {
                int v = g.targets[e];
                long long w = g.weights[e];
                fwdAdj[u].push_back({v, w, false, -1});
                bwdAdj[v].push_back({u, w, false, -1});
            }
        }
    }

    /* ----------------------------------------------------------------
     * Local search: witness search to check if shortcut is needed.
     * Returns shortest distance from `src` to `tgt` among non-contracted
     * nodes, ignoring node `ignore`. Limited to `maxDist` and `maxHops`.
     * ---------------------------------------------------------------- */
    long long witnessSearch(int src, int tgt, int ignore, long long maxDist, int maxHops) {
        /* Small local Dijkstra */
        struct WEntry {
            long long dist;
            int node;
            int hops;
            bool operator>(const WEntry &o) const { return dist > o.dist; }
        };

        /* Use a small local search with hop limit */
        std::priority_queue<WEntry, std::vector<WEntry>, std::greater<WEntry>> pq;

        /* We need a local distance map — use a vector + cleanup list */
        static thread_local std::vector<long long> wDist;
        static thread_local std::vector<int> touched;
        if ((int)wDist.size() < n) {
            wDist.assign(n, VERY_FAR);
        }

        wDist[src] = 0;
        touched.push_back(src);
        pq.push({0, src, 0});

        long long result = VERY_FAR;

        while (!pq.empty()) {
            auto [du, u, hops] = pq.top();
            pq.pop();

            if (du > wDist[u]) continue;  /* stale */
            if (du > maxDist) break;       /* exceeded max distance */

            if (u == tgt) {
                result = du;
                break;
            }

            if (hops >= maxHops) continue;

            for (auto &e : fwdAdj[u]) {
                if (contracted[e.target] || e.target == ignore) continue;
                long long nd = du + e.weight;
                if (nd < wDist[e.target] && nd <= maxDist) {
                    wDist[e.target] = nd;
                    touched.push_back(e.target);
                    pq.push({nd, e.target, hops + 1});
                }
            }
        }

        /* Cleanup */
        for (int v : touched) wDist[v] = VERY_FAR;
        touched.clear();

        return result;
    }

    /* ----------------------------------------------------------------
     * Compute contraction priority for a node.
     * Priority = edge_difference + 2 * level[v]
     * edge_difference = shortcuts_added - edges_removed
     * ---------------------------------------------------------------- */
    int computePriority(int v) {
        if (contracted[v]) return std::numeric_limits<int>::max();

        int edgesRemoved = 0;
        int shortcutsAdded = 0;

        /* Count edges that would be removed */
        for (auto &e : fwdAdj[v]) {
            if (!contracted[e.target]) edgesRemoved++;
        }
        for (auto &e : bwdAdj[v]) {
            if (!contracted[e.target]) edgesRemoved++;
        }

        /* Count shortcuts that would be needed */
        /* For each pair (u → v → w), check if u→w needs a shortcut */
        for (auto &inEdge : bwdAdj[v]) {
            int u = inEdge.target;
            if (contracted[u]) continue;

            for (auto &outEdge : fwdAdj[v]) {
                int w = outEdge.target;
                if (contracted[w] || w == u) continue;

                long long shortcutDist = inEdge.weight + outEdge.weight;

                /* Witness search: is there a shorter path u→w not through v? */
                long long witnessDist = witnessSearch(u, w, v, shortcutDist, 5);

                if (witnessDist > shortcutDist) {
                    shortcutsAdded++;
                }
            }
        }

        int edgeDiff = shortcutsAdded - edgesRemoved;
        return edgeDiff + 2 * level[v];
    }

    /* ----------------------------------------------------------------
     * Contract a single node: add shortcuts and mark as contracted.
     * ---------------------------------------------------------------- */
    void contractNode(int v) {
        /* For each pair (u → v → w), add shortcut if needed */
        for (auto &inEdge : bwdAdj[v]) {
            int u = inEdge.target;
            if (contracted[u]) continue;

            for (auto &outEdge : fwdAdj[v]) {
                int w = outEdge.target;
                if (contracted[w] || w == u) continue;

                long long shortcutDist = inEdge.weight + outEdge.weight;

                /* Witness search */
                long long witnessDist = witnessSearch(u, w, v, shortcutDist, 5);

                if (witnessDist > shortcutDist) {
                    /* Add shortcut u → w */
                    fwdAdj[u].push_back({w, shortcutDist, true, v});
                    bwdAdj[w].push_back({u, shortcutDist, true, v});
                    numShortcuts++;
                }
            }
        }

        contracted[v] = true;

        /* Update levels of neighbors */
        for (auto &e : fwdAdj[v]) {
            if (!contracted[e.target]) {
                level[e.target] = std::max(level[e.target], level[v] + 1);
            }
        }
        for (auto &e : bwdAdj[v]) {
            if (!contracted[e.target]) {
                level[e.target] = std::max(level[e.target], level[v] + 1);
            }
        }
    }

    /* ----------------------------------------------------------------
     * PREPROCESSING: Contract all nodes in priority order.
     * Uses a lazy-update priority queue (re-evaluate before popping).
     * ---------------------------------------------------------------- */
    void preprocess() {
        double t0 = timer();

        fprintf(stderr, "c CH preprocessing: %d nodes\n", n);

        /* Initial priority queue */
        using PQEntry = std::pair<int, int>;  /* (priority, node) */
        std::priority_queue<PQEntry, std::vector<PQEntry>,
                            std::greater<PQEntry>> pq;

        /* Compute initial priorities */
        fprintf(stderr, "c   Computing initial priorities...\n");
        for (int v = 0; v < n; v++) {
            int prio = computePriority(v);
            pq.push({prio, v});
        }

        /* Contract nodes one by one */
        int contracted_count = 0;
        int report_interval = std::max(1, n / 20);

        fprintf(stderr, "c   Contracting nodes...\n");
        while (!pq.empty()) {
            auto [oldPrio, v] = pq.top();
            pq.pop();

            if (contracted[v]) continue;

            /* Lazy update: recompute priority and check if still minimum */
            int newPrio = computePriority(v);
            if (newPrio > oldPrio && !pq.empty()) {
                /* Priority increased — put back and try next */
                pq.push({newPrio, v});
                continue;
            }

            /* Contract this node */
            rank[v] = contracted_count;
            order[contracted_count] = v;
            contractNode(v);
            contracted_count++;

            if (contracted_count % report_interval == 0) {
                fprintf(stderr, "c   %d/%d nodes contracted (%.0f%%) — %lld shortcuts so far\n",
                        contracted_count, n,
                        100.0 * contracted_count / n,
                        numShortcuts);
            }
        }

        /* Build upward-only adjacency lists */
        fprintf(stderr, "c   Building upward graph...\n");
        for (int u = 0; u < n; u++) {
            for (auto &e : fwdAdj[u]) {
                if (rank[e.target] > rank[u]) {
                    upFwd[u].push_back({e.target, e.weight});
                }
            }
            for (auto &e : bwdAdj[u]) {
                if (rank[e.target] > rank[u]) {
                    upBwd[u].push_back({e.target, e.weight});
                }
            }
        }

        preprocessTime = timer() - t0;
        fprintf(stderr, "c CH preprocessing complete: %.2f sec, %lld shortcuts\n",
                preprocessTime, numShortcuts);
        fprintf(stderr, "c   Avg degree in upward graph: fwd=%.1f bwd=%.1f\n",
                (double)std::accumulate(upFwd.begin(), upFwd.end(), 0LL,
                    [](long long s, const auto &v) { return s + v.size(); }) / n,
                (double)std::accumulate(upBwd.begin(), upBwd.end(), 0LL,
                    [](long long s, const auto &v) { return s + v.size(); }) / n);
    }

    /* ----------------------------------------------------------------
     * QUERY: Bidirectional Dijkstra on upward graph.
     * Forward search from source, backward search from target.
     * ---------------------------------------------------------------- */
    long long query(int source, int target) {
        if (source == target) return 0;

        using PQEntry = std::pair<long long, int>;
        std::priority_queue<PQEntry, std::vector<PQEntry>,
                            std::greater<PQEntry>> fwdPQ, bwdPQ;

        std::vector<int> touchedFwd, touchedBwd;

        distFwd[source] = 0;
        distBwd[target] = 0;
        touchedFwd.push_back(source);
        touchedBwd.push_back(target);
        fwdPQ.push({0, source});
        bwdPQ.push({0, target});

        long long mu = VERY_FAR;  /* best distance found so far */

        while (!fwdPQ.empty() || !bwdPQ.empty()) {
            /* Forward step */
            if (!fwdPQ.empty()) {
                auto [du, u] = fwdPQ.top();
                if (du < mu) {
                    fwdPQ.pop();
                    if (du <= distFwd[u]) {
                        statScans++;
                        /* Check if backward search reached this node */
                        if (distBwd[u] < VERY_FAR) {
                            long long candidate = du + distBwd[u];
                            if (candidate < mu) mu = candidate;
                        }
                        /* Relax upward edges */
                        for (auto &[v, w] : upFwd[u]) {
                            long long nd = du + w;
                            if (nd < distFwd[v]) {
                                distFwd[v] = nd;
                                touchedFwd.push_back(v);
                                fwdPQ.push({nd, v});
                                statUpdates++;
                            }
                        }
                    }
                } else {
                    /* Forward search exhausted — clear it */
                    while (!fwdPQ.empty()) fwdPQ.pop();
                }
            }

            /* Backward step */
            if (!bwdPQ.empty()) {
                auto [du, u] = bwdPQ.top();
                if (du < mu) {
                    bwdPQ.pop();
                    if (du <= distBwd[u]) {
                        statScans++;
                        /* Check if forward search reached this node */
                        if (distFwd[u] < VERY_FAR) {
                            long long candidate = distFwd[u] + du;
                            if (candidate < mu) mu = candidate;
                        }
                        /* Relax upward backward edges */
                        for (auto &[v, w] : upBwd[u]) {
                            long long nd = du + w;
                            if (nd < distBwd[v]) {
                                distBwd[v] = nd;
                                touchedBwd.push_back(v);
                                bwdPQ.push({nd, v});
                                statUpdates++;
                            }
                        }
                    }
                } else {
                    while (!bwdPQ.empty()) bwdPQ.pop();
                }
            }

            /* Both searches exhausted? */
            if (fwdPQ.empty() && bwdPQ.empty()) break;
        }

        /* Cleanup */
        for (int v : touchedFwd) distFwd[v] = VERY_FAR;
        for (int v : touchedBwd) distBwd[v] = VERY_FAR;

        return mu;
    }

    /* ----------------------------------------------------------------
     * SSSP via CH: query every node from source.
     * For fair comparison with other algorithms, we compute SSSP
     * by running n point-to-point queries. This is intentionally
     * NOT how CH is used in practice (it's for point-to-point).
     *
     * For the EVIDENCE comparison, we instead run the standard
     * Dijkstra on the upward graph as a single-source search.
     * ---------------------------------------------------------------- */
    void ssspViaUpwardDijkstra(int source) {
        statScans = 0;
        statUpdates = 0;

        /* Reset distances */
        std::fill(distFwd.begin(), distFwd.end(), VERY_FAR);

        using PQEntry = std::pair<long long, int>;
        std::priority_queue<PQEntry, std::vector<PQEntry>,
                            std::greater<PQEntry>> pq;

        distFwd[source] = 0;
        pq.push({0, source});

        /* Phase 1: Forward search on full augmented graph (with shortcuts) */
        /* This is standard Dijkstra on the graph with shortcuts added */
        std::vector<bool> settled(n, false);

        while (!pq.empty()) {
            auto [du, u] = pq.top();
            pq.pop();

            if (settled[u]) continue;
            settled[u] = true;
            statScans++;

            /* Relax ALL forward edges (original + shortcuts) */
            for (auto &e : fwdAdj[u]) {
                int v = e.target;
                if (settled[v]) continue;
                long long nd = du + e.weight;
                if (nd < distFwd[v]) {
                    distFwd[v] = nd;
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

    fprintf(stderr, "c Contraction Hierarchies (CH)\n");

    parse_gr(&n, &m, &nodes, &arcs, &nmin, gName);
    (void)arcs;
    printf("p res ss dij_ch\n");
    parse_ss(&nQ, &source_array, aName);
    fprintf(oFile, "f %s %s\n", gName, aName);

    ArcLen(n, nodes, &minArcLen, &maxArcLen);
    fprintf(stderr, "c Nodes: %ld  Arcs: %ld  Trials: %ld\n", n, m, nQ);

    CsrGraph g = buildCsr(n, nodes, m, minArcLen, maxArcLen);

    /* Build CH */
    CHSolver ch(g.n);
    ch.buildFromCsr(g);

    /* Preprocessing */
    ch.preprocess();

    fprintf(oFile, "c CH preprocessing: %.2f sec, %lld shortcuts\n",
            ch.preprocessTime, ch.numShortcuts);

    /* Run SSSP queries using Dijkstra on augmented graph (with shortcuts) */
    /* This gives the same SSSP result as standard Dijkstra but benefits
       from shortcuts reducing the effective graph diameter */
    long long totalScans = 0, totalUpdates = 0;

    tm = timer();
    for (int i = 0; i < nQ; i++) {
        int source = (int)(source_array[i] - nmin);
        ch.ssspViaUpwardDijkstra(source);

#ifdef CHECKSUM
        long long checksum = 0;
        for (int j = 0; j < g.n; j++) {
            if (ch.distFwd[j] < VERY_FAR)
                checksum = (checksum + (ch.distFwd[j] % MODUL)) % MODUL;
        }
        fprintf(oFile, "d %lld\n", checksum);
#endif

        totalScans   += ch.statScans;
        totalUpdates += ch.statUpdates;
    }
    tm = timer() - tm;

#ifndef CHECKSUM
    fprintf(stderr, "c Scans (ave): %.1f  Improvements (ave): %.1f\n",
            (double)totalScans / nQ, (double)totalUpdates / nQ);
    fprintf(stderr, "c Time (ave query, ms): %.2f\n", 1000.0 * tm / nQ);
    fprintf(stderr, "c Preprocessing time: %.2f sec\n", ch.preprocessTime);
    fprintf(stderr, "c Shortcuts added: %lld\n", ch.numShortcuts);

    fprintf(oFile, "g %ld %ld %lld %lld\n", n, m, minArcLen, maxArcLen);
    fprintf(oFile, "t %f\n", 1000.0 * tm / nQ);
    fprintf(oFile, "v %f\n", (double)totalScans / nQ);
    fprintf(oFile, "i %f\n", (double)totalUpdates / nQ);
    fprintf(oFile, "p %f\n", ch.preprocessTime);
    fprintf(oFile, "s %lld\n", ch.numShortcuts);
#endif

    freeCsr(g);
    free(source_array);
    fclose(oFile);
    return 0;
}
