#!/bin/bash
#
# merge_and_postprocess.sh — Merge stats from Run #1 into Run #2 and regenerate
# Section 6 (Scalability) + Summary tables that were empty/truncated.
#
# IDEMPOTENT: Safe to re-run. Checks if data already merged before appending.
#
# NOTE: Not using set -e because grep returning no-match (exit 1) is expected.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/benchmarks/results"
DATA_DIR="${DATA_DIR:-${PROJECT_ROOT}/data}"

# --- Source files ---
ORIG_STATS="${RESULTS_DIR}/full_stats_20260403_155504.csv"
ORIG_BUILD="${RESULTS_DIR}/full_build_20260403_155504.csv"
ORIG_CHECKSUMS="${RESULTS_DIR}/full_checksums_20260403_155504.csv"
ORIG_MEMORY="${RESULTS_DIR}/full_memory_20260403_155504.csv"

NEW_STATS="${RESULTS_DIR}/full_stats_20260405_140552.csv"
NEW_BUILD="${RESULTS_DIR}/full_build_20260405_140552.csv"
NEW_CHECKSUMS="${RESULTS_DIR}/full_checksums_20260405_140552.csv"
NEW_MEMORY="${RESULTS_DIR}/full_memory_20260405_140552.csv"
NEW_SCALABILITY="${RESULTS_DIR}/full_scalability_20260405_140552.csv"

STATS_CSV="${NEW_STATS}"
SCALABILITY_CSV="${NEW_SCALABILITY}"

# --- Configuration (must match run_full_benchmark.sh) ---
ROAD_GRAPHS=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
)

# Only grids that actually completed in Run #1
GRID_GRAPHS=(
    "grid_100x100_w100"
    "grid_100x100_w100000"
    "grid_316x316_w100"
    "grid_316x316_w100000"
    "grid_1000x1000_w100"
    "grid_1000x1000_w100000"
    "grid_3162x3162_w100"
    # grid_3162x3162_w100000 — did NOT complete (OOM/timeout on 10M nodes)
)

CORE_IMPLS=(
    "bh:dij_bh:dij_bhC"
    "4h:dij_4h:dij_4hC"
    "fh:dij_fh:dij_fhC"
    "ph:dij_ph:dij_phC"
    "dial:dij_dial:dij_dialC"
    "r1:dij_r1:dij_r1C"
    "r2:dij_r2:dij_r2C"
    "ombi:ombi:ombiC"
    "ombi_v3:ombi_v3:ombi_v3C"
    "sq:sq:sqC"
    "ch:dij_ch:dij_chC"
)

TOTAL_RUNS=11
WARMUP_RUNS=1
EFF_RUNS=$((TOTAL_RUNS - 2))
T_CRIT_95_DF8=2.306

HAS_GTIME=0
if /usr/bin/time --version 2>&1 | grep -q "GNU"; then
    HAS_GTIME=1
fi

get_node_count() {
    grep '^p sp' "$1" | head -1 | awk '{print $3}'
}

# =====================================================================
# STEP 1: Merge CSV data (IDEMPOTENT — skip if already done)
# =====================================================================
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  MERGE & POST-PROCESS: Combining Run #1 + Run #2 data"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Check if stats already merged by looking for a known Run #1 row
if grep -q "USA-road-t.BAY,road,bh," "${NEW_STATS}" 2>/dev/null; then
    echo "  ⏭️  Stats CSV already has Run #1 data — skipping merge"
else
    orig_count=$(tail -n +2 "${ORIG_STATS}" | wc -l)
    echo "  Merging stats: ${orig_count} rows from Run #1"
    tail -n +2 "${ORIG_STATS}" >> "${NEW_STATS}"
fi

if grep -q "^ombi," "${NEW_BUILD}" 2>/dev/null; then
    echo "  ⏭️  Build CSV already has Run #1 data — skipping merge"
else
    tail -n +2 "${ORIG_BUILD}" >> "${NEW_BUILD}"
    echo "  ✅ Merged build CSV"
fi

if grep -q "USA-road-t.BAY,road,bh," "${NEW_CHECKSUMS}" 2>/dev/null; then
    echo "  ⏭️  Checksums CSV already has Run #1 data — skipping merge"
else
    tail -n +2 "${ORIG_CHECKSUMS}" >> "${NEW_CHECKSUMS}"
    echo "  ✅ Merged checksums CSV"
fi

if grep -q "USA-road-t.BAY,road,bh," "${NEW_MEMORY}" 2>/dev/null; then
    echo "  ⏭️  Memory CSV already has Run #1 data — skipping merge"
else
    tail -n +2 "${ORIG_MEMORY}" >> "${NEW_MEMORY}"
    echo "  ✅ Merged memory CSV"
fi

new_count=$(tail -n +2 "${NEW_STATS}" | wc -l)
echo ""
echo "  Stats CSV: ${new_count} data rows"
echo ""

# =====================================================================
# STEP 2: Regenerate Section 6 — Scalability Analysis
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SECTION 6: Scalability Analysis — Time vs Graph Size                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Extracting node counts and computing log-log regression..."
echo ""

# Always regenerate scalability CSV
echo "graph_type,impl,graph,nodes,median_ms,log_nodes,log_ms" > "${SCALABILITY_CSV}"

for graph in "${ROAD_GRAPHS[@]}"; do
    gr_file="${DATA_DIR}/${graph}.gr"
    if [ ! -f "${gr_file}" ]; then
        echo "  ⚠️  Skipping ${graph} — .gr file not found"
        continue
    fi
    nodes=$(get_node_count "${gr_file}")

    while IFS=, read -r g gt impl median rest; do
        if [ "${g}" = "${graph}" ] && [ "${gt}" = "road" ]; then
            log_n=$(echo "${nodes}" | awk '{printf "%.4f", log($1)/log(10)}')
            log_t=$(echo "${median}" | awk '{printf "%.4f", log($1)/log(10)}')
            echo "road,${impl},${graph},${nodes},${median},${log_n},${log_t}" >> "${SCALABILITY_CSV}"
        fi
    done < <(tail -n +2 "${STATS_CSV}")
done

scalability_rows=$(tail -n +2 "${SCALABILITY_CSV}" | wc -l)
echo "  Scalability CSV: ${scalability_rows} data rows"
echo ""

printf "  %-10s │ %14s │ %s\n" "Impl" "Slope(log-log)" "Interpretation"
echo "  ───────────┼────────────────┼──────────────────────────────────────"

# Compute slopes — use a temp file to avoid subshell issues
SLOPE_IMPLS=$(tail -n +2 "${SCALABILITY_CSV}" 2>/dev/null | cut -d, -f2 | sort -u)
for impl in ${SLOPE_IMPLS}; do
    slope=$(grep ",${impl}," "${SCALABILITY_CSV}" | awk -F, '
    BEGIN { n=0; sx=0; sy=0; sxy=0; sxx=0 }
    {
        x=$6; y=$7
        sx+=x; sy+=y; sxy+=x*y; sxx+=x*x; n++
    }
    END {
        if (n<2) { print "N/A"; exit }
        slope = (n*sxy - sx*sy) / (n*sxx - sx*sx)
        printf "%.3f", slope
    }')

    interp=""
    if [ "${slope}" != "N/A" ]; then
        # Use awk instead of bc for portability
        interp=$(echo "${slope}" | awk '{
            if ($1 < 1.1) print "≈ O(n) — near-linear"
            else if ($1 < 1.3) print "≈ O(n log n) — expected for Dijkstra"
            else if ($1 < 1.6) print "≈ O(n^1.5) — superlinear"
            else printf "≈ O(n^%.1f) — check for issues", $1
        }')
    fi

    printf "  %-10s │ %14s │ %s\n" "${impl}" "${slope}" "${interp}"
done

echo ""
echo "  Slope = d(log time) / d(log nodes). For Dijkstra with a good PQ,"
echo "  expect ~1.0–1.2 on road networks (near-linear in practice due to"
echo "  sparse graphs and small average degree)."
echo ""

# =====================================================================
# STEP 3: Summary Tables
# =====================================================================

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SUMMARY: Speed Ratio vs Binary Heap — Road Networks (lower = faster)      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
printf "  %-10s" "Impl"
for graph in "${ROAD_GRAPHS[@]}"; do
    short="${graph#USA-road-t.}"
    printf " │ %8s" "${short}"
done
echo ""
printf "  ──────────"
for graph in "${ROAD_GRAPHS[@]}"; do
    printf "─┼──────────"
done
echo ""

for impl_spec in "${CORE_IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    printf "  %-10s" "${label}"
    for graph in "${ROAD_GRAPHS[@]}"; do
        ratio=$(grep "^${graph},road,${label}," "${STATS_CSV}" 2>/dev/null | head -1 | cut -d, -f17)
        printf " │ %8s" "${ratio:-N/A}"
    done
    echo ""
done
echo ""

# Grid summary
if [ ${#GRID_GRAPHS[@]} -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SUMMARY: Speed Ratio vs Binary Heap — Grid Graphs (lower = faster)        ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    for wlabel in "w100" "w100000"; do
        echo "  --- Weight range: ${wlabel} ---"
        printf "  %-10s" "Impl"
        local_grids=()
        for graph in "${GRID_GRAPHS[@]}"; do
            case "${graph}" in
                *"${wlabel}")
                    local_grids+=("${graph}")
                    short="${graph%%_${wlabel}}"
                    short="${short#grid_}"
                    printf " │ %12s" "${short}"
                    ;;
            esac
        done
        echo ""
        printf "  ──────────"
        for _ in "${local_grids[@]}"; do
            printf "─┼──────────────"
        done
        echo ""

        for impl_spec in "${CORE_IMPLS[@]}"; do
            IFS=':' read -r label tbin cbin <<< "${impl_spec}"
            printf "  %-10s" "${label}"
            for graph in "${local_grids[@]}"; do
                ratio=$(grep "^${graph},grid,${label}," "${STATS_CSV}" 2>/dev/null | head -1 | cut -d, -f17)
                printf " │ %12s" "${ratio:-N/A}"
            done
            echo ""
        done
        echo ""
    done
fi

# Memory summary
if [ "${HAS_GTIME}" -eq 1 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SUMMARY: Peak RSS Memory (KB) — Road Networks                             ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  %-10s" "Impl"
    for graph in "${ROAD_GRAPHS[@]}"; do
        short="${graph#USA-road-t.}"
        printf " │ %10s" "${short}"
    done
    echo ""
    printf "  ──────────"
    for graph in "${ROAD_GRAPHS[@]}"; do
        printf "─┼────────────"
    done
    echo ""

    for impl_spec in "${CORE_IMPLS[@]}"; do
        IFS=':' read -r label tbin cbin <<< "${impl_spec}"
        printf "  %-10s" "${label}"
        for graph in "${ROAD_GRAPHS[@]}"; do
            mem=$(grep "^${graph},road,${label}," "${STATS_CSV}" 2>/dev/null | head -1 | cut -d, -f13)
            printf " │ %10s" "${mem:-N/A}"
        done
        echo ""
    done
    echo ""
fi

# =====================================================================
# STATISTICAL DETAIL TABLE
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  STATISTICAL DETAIL: Full Timing Distribution                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
printf "  %-20s %-10s │ %10s │ %10s │ %10s │ %10s │ %10s │ %18s\n" \
       "Graph" "Impl" "Median" "Mean" "StdDev" "Min" "Max" "95% CI"
echo "  ──────────────────── ───────────┼────────────┼────────────┼────────────┼────────────┼────────────┼────────────────────"

tail -n +2 "${STATS_CSV}" | while IFS=, read -r graph gtype impl median mean stddev min_v max_v ci_low ci_high rest; do
    short="${graph#USA-road-t.}"
    ci_str="[$(echo "${ci_low}" | awk '{printf "%.3f",$1}'),$(echo "${ci_high}" | awk '{printf "%.3f",$1}')]"
    printf "  %-20s %-10s │ %10s │ %10s │ %10s │ %10s │ %10s │ %18s\n" \
           "${short}" "${impl}" \
           "$(echo "${median}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${mean}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${stddev}" | awk '{printf "%.4f",$1}')" \
           "$(echo "${min_v}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${max_v}" | awk '{printf "%.3f",$1}')" \
           "${ci_str}"
done
echo ""

# =====================================================================
# FAIRNESS & METHODOLOGY NOTES
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  FAIRNESS & METHODOLOGY NOTES                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  COMPILER:       g++ -std=c++17 -Wall -O3 -DNDEBUG (identical for all)"
echo "  TIMING:         ${TOTAL_RUNS} runs, drop min & max → ${EFF_RUNS} effective."
echo "                  ${WARMUP_RUNS} warmup run(s) (untimed) before measurement."
echo "  STATISTICS:     Median (primary), mean, stddev, min, max, 95% CI."
echo "                  CI: t-distribution (df=$((EFF_RUNS-1)), t=${T_CRIT_95_DF8})."
echo ""
echo "  SCANS (v):      Nodes dequeued & settled. Should be identical across all"
echo "                  correct Dijkstra variants. Small differences = tie-breaking."
echo ""
echo "  UPDATES (i):    CRITICAL FAIRNESS CAVEAT:"
echo "    BH,4H,FH,PH,Dial,R1,R2,OMBI: count every dist[v] improvement."
echo "    SQ (Goldberg): counts BUCKET MOVES only (bckOld != bckNew)."
echo "    SQ 'i' is LOWER and NOT directly comparable. Marked with (*)."
echo ""
echo "  MEMORY:         Peak RSS via GNU /usr/bin/time -v. Includes graph storage."
echo "                  Delta between impls = priority queue overhead."
echo ""
echo "  SCALABILITY:    Log-log regression of median time vs node count."
echo "                  Slope ~1.0 = near-linear. Slope ~1.2 = O(n log n)."
echo ""
echo "  GRAPHS:"
echo "    Road:  Real DIMACS 9th Challenge road networks (BAY/COL/FLA/NW/NE)."
echo "    Grid:  Synthetic WxW grids, uniform degree-4, random weights."
echo "      w100    — narrow [1,100]: many bucket collisions"
echo "      w100000 — wide [1,100000]: spread across buckets"
echo "      Note: grid_3162x3162_w100000 did not complete (resource limits)."
echo ""
echo "  OMBI VARIANTS:"
echo "    ombi      — Standard (ombi.cc): simpler, baseline correctness."
echo "    ombi_opt  — Optimized: packed state, pool alloc, force-inline."
echo "    ombi_v2   — Caliber/F-set: exact-distance vertices skip buckets."
echo "    ombi_v3   — Two-level bitmap: fastest variant."
echo ""
echo "  SENSITIVITY:"
echo "    BW_MULT:     Bucket width = BW_MULT x minArcLen."
echo "                 Default=4. Tested: {1,2,3,4,6,8}."
echo "    HOT_BUCKETS: Number of hot-zone circular buckets."
echo "                 Default=2^14 (16384). Tested: 2^10..2^18."
echo ""
echo "  CORRECTNESS:   MD5 of all source->distance checksums vs BH reference."
echo ""

# =====================================================================
# DONE
# =====================================================================
echo "==============================================================================="
echo "  Merged output files:"
echo "    Statistics:     ${STATS_CSV}"
echo "    Scalability:    ${SCALABILITY_CSV}"
echo "    Build info:     ${NEW_BUILD}"
echo "    Checksums:      ${NEW_CHECKSUMS}"
echo "    Memory:         ${NEW_MEMORY}"
echo ""
echo "  Post-processing complete."
echo "==============================================================================="
