#!/bin/bash
#
# run_full_benchmark.sh — Comprehensive FAIR benchmark: OMBI vs all baselines
#
# Measures: time, scans, relaxations, peak memory, ns/operation, throughput,
#           scalability ratios, correctness checksums.
#
# Fairness notes:
#   - SQ's "i" (cUpdates) counts BUCKET MOVES, not true relaxations.
#     All other implementations count true dist[] improvements.
#     The summary marks SQ's relaxation column with (*) to flag this.
#   - Memory is measured via /usr/bin/time -v (MaxRSS).
#   - All implementations use identical compiler flags (-O3 -std=c++17 -DNDEBUG).
#
# Usage:
#   cd /mnt/d/Projects/Practice/Research/ombi
#   make all
#   ./benchmarks/scripts/run_full_benchmark.sh 2>&1 | tee benchmarks/results/full_benchmark_$(date +%Y%m%d_%H%M%S).log
#

set -euo pipefail

# =====================================================================
# CONFIGURATION
# =====================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/bin"
RESULTS_DIR="${PROJECT_ROOT}/benchmarks/results"
DATA_DIR="${DATA_DIR:-${PROJECT_ROOT}/data}"

RUNS=5  # Number of timing runs (median reported)

GRAPHS=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
    # "USA-road-t.USA"   # Uncomment for full USA (23.9M nodes — very slow!)
)

# All implementations: label:timing_binary:checksum_binary
IMPLS=(
    "bh:dij_bh:dij_bhC"
    "4h:dij_4h:dij_4hC"
    "fh:dij_fh:dij_fhC"
    "ph:dij_ph:dij_phC"
    "dial:dij_dial:dij_dialC"
    "r1:dij_r1:dij_r1C"
    "r2:dij_r2:dij_r2C"
    "ombi:ombi:ombiC"
    "sq:sq:sqC"
)

# =====================================================================
# VALIDATION
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  OMBI — Comprehensive Fair Benchmark Suite                         ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Project root: ${PROJECT_ROOT}"
echo "  Data dir:     ${DATA_DIR}"
echo "  Runs:         ${RUNS} (median reported)"
echo "  Date:         $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check binaries
missing=0
for impl_spec in "${IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    for b in "${tbin}" "${cbin}"; do
        if [ ! -f "${BIN_DIR}/${b}" ]; then
            echo "  ❌ Missing: bin/${b}"
            missing=1
        fi
    done
done
if [ "${missing}" -eq 1 ]; then
    echo ""
    echo "  Run 'make all' first."
    exit 1
fi
echo "  ✅ All binaries found"

# Check data
if [ ! -d "${DATA_DIR}" ]; then
    echo "  ❌ DATA_DIR not found: ${DATA_DIR}"
    exit 1
fi
echo "  ✅ Data directory found"

# Check /usr/bin/time
HAS_GTIME=0
if /usr/bin/time --version 2>&1 | grep -q "GNU"; then
    HAS_GTIME=1
    echo "  ✅ GNU time available (memory measurement enabled)"
else
    echo "  ⚠️  GNU time not available (memory measurement disabled)"
fi
echo ""

mkdir -p "${RESULTS_DIR}"

# =====================================================================
# OUTPUT FILES
# =====================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RAW_CSV="${RESULTS_DIR}/full_raw_${TIMESTAMP}.csv"
SUMMARY_CSV="${RESULTS_DIR}/full_summary_${TIMESTAMP}.csv"
MEMORY_CSV="${RESULTS_DIR}/full_memory_${TIMESTAMP}.csv"
CHECKSUM_CSV="${RESULTS_DIR}/full_checksums_${TIMESTAMP}.csv"

echo "graph,impl,run,time_ms,scans,updates,peak_rss_kb" > "${RAW_CSV}"
echo "graph,impl,median_ms,avg_scans,avg_updates,peak_rss_kb,ns_per_scan,ns_per_update,throughput_nodes_per_sec,ratio_vs_bh,checksum_ok" > "${SUMMARY_CSV}"
echo "graph,impl,peak_rss_kb" > "${MEMORY_CSV}"
echo "graph,impl,checksum_md5,match_bh" > "${CHECKSUM_CSV}"

# =====================================================================
# HELPER: extract median from array
# =====================================================================
get_median() {
    local -a arr=("$@")
    local n=${#arr[@]}
    IFS=$'\n' sorted=($(sort -g <<<"${arr[*]}")); unset IFS
    local mid=$((n / 2))
    echo "${sorted[$mid]}"
}

# =====================================================================
# RUN BENCHMARKS
# =====================================================================
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

# Associative arrays for summary
declare -A BH_MEDIAN  # store BH median per graph for ratio calculation

for graph in "${GRAPHS[@]}"; do
    gr_file="${DATA_DIR}/${graph}.gr"
    ss_file="${DATA_DIR}/${graph}.ss"
    short="${graph#USA-road-t.}"

    if [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ]; then
        echo "  ⚠️  SKIP: ${graph} (missing .gr or .ss)"
        continue
    fi

    echo "┌─────────────────────────────────────────────────────────────────────"
    echo "│  Graph: ${short}"
    echo "├─────────────────────────────────────────────────────────────────────"
    printf "│  %-6s │ %10s │ %12s │ %12s │ %10s │ %10s │ %s\n" \
           "Impl" "Median(ms)" "Scans" "Updates" "RSS(KB)" "ns/scan" "✓"
    echo "│  ───────┼────────────┼──────────────┼──────────────┼────────────┼────────────┼───"

    ref_checksum=""

    for impl_spec in "${IMPLS[@]}"; do
        IFS=':' read -r label tbin cbin <<< "${impl_spec}"

        # --- Timing runs ---
        times=()
        last_scans="N/A"
        last_updates="N/A"
        for run in $(seq 1 ${RUNS}); do
            out_file="${RESULTS_DIR}/.tmp_${label}_${short}_run${run}.txt"
            rm -f "${out_file}"

            # Run with memory measurement if available
            rss_kb="N/A"
            if [ "${HAS_GTIME}" -eq 1 ] && [ "${run}" -eq 1 ]; then
                time_out=$(/usr/bin/time -v "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${out_file}" 2>&1 || true)
                rss_line=$(echo "${time_out}" | grep "Maximum resident set size" || true)
                if [ -n "${rss_line}" ]; then
                    rss_kb=$(echo "${rss_line}" | awk '{print $NF}')
                fi
            else
                "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${out_file}" 2>/dev/null || true
            fi

            t_ms=$(grep '^t ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "0")
            scans=$(grep '^v ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "0")
            updates=$(grep '^i ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "0")

            times+=("${t_ms}")
            last_scans="${scans}"
            last_updates="${updates}"

            echo "${graph},${label},${run},${t_ms},${scans},${updates},${rss_kb}" >> "${RAW_CSV}"
            rm -f "${out_file}"
        done

        # Median time
        median_ms=$(get_median "${times[@]}")

        # Memory (from run 1)
        mem_kb=$(grep "^${graph},${label},1," "${RAW_CSV}" | head -1 | cut -d, -f7)
        if [ "${mem_kb}" = "N/A" ] || [ -z "${mem_kb}" ]; then
            mem_kb="N/A"
        fi

        # --- Checksum verification ---
        cout_file="${RESULTS_DIR}/.tmp_${label}_${short}_chk.txt"
        rm -f "${cout_file}"
        "${BIN_DIR}/${cbin}" "${gr_file}" "${ss_file}" "${cout_file}" 2>/dev/null || true
        chk_md5=$(grep '^d ' "${cout_file}" 2>/dev/null | md5sum | awk '{print $1}')
        rm -f "${cout_file}"

        if [ "${label}" = "bh" ]; then
            ref_checksum="${chk_md5}"
        fi

        if [ "${chk_md5}" = "${ref_checksum}" ]; then
            match="✅"
            match_csv="YES"
        else
            match="❌"
            match_csv="NO"
        fi

        # Derived metrics
        ns_per_scan="N/A"
        ns_per_update="N/A"
        throughput="N/A"
        if [ "${last_scans}" != "0" ] && [ "${last_scans}" != "N/A" ]; then
            ns_per_scan=$(echo "${median_ms} ${last_scans}" | awk '{printf "%.1f", ($1 * 1000000.0) / $2}')
            throughput=$(echo "${median_ms} ${last_scans}" | awk '{printf "%.0f", ($2 * 1000.0) / $1}')
        fi
        if [ "${last_updates}" != "0" ] && [ "${last_updates}" != "N/A" ]; then
            ns_per_update=$(echo "${median_ms} ${last_updates}" | awk '{printf "%.1f", ($1 * 1000000.0) / $2}')
        fi

        # Store BH median for ratio
        if [ "${label}" = "bh" ]; then
            BH_MEDIAN["${graph}"]="${median_ms}"
        fi

        # Ratio vs BH
        ratio="N/A"
        bh_med="${BH_MEDIAN[${graph}]:-}"
        if [ -n "${bh_med}" ] && [ "${bh_med}" != "0" ]; then
            ratio=$(echo "${median_ms} ${bh_med}" | awk '{printf "%.3f", $1 / $2}')
        fi

        # Print row
        updates_display="${last_updates}"
        if [ "${label}" = "sq" ]; then
            updates_display="${last_updates}(*)"
        fi

        printf "│  %-6s │ %10s │ %12s │ %12s │ %10s │ %10s │ %s\n" \
               "${label}" "${median_ms}" "${last_scans}" "${updates_display}" \
               "${mem_kb}" "${ns_per_scan}" "${match}"

        # Write to summary CSV
        echo "${graph},${label},${median_ms},${last_scans},${last_updates},${mem_kb},${ns_per_scan},${ns_per_update},${throughput},${ratio},${match_csv}" >> "${SUMMARY_CSV}"
        echo "${graph},${label},${chk_md5},${match_csv}" >> "${CHECKSUM_CSV}"
        if [ "${mem_kb}" != "N/A" ]; then
            echo "${graph},${label},${mem_kb}" >> "${MEMORY_CSV}"
        fi
    done

    echo "│"
    echo "│  (*) SQ 'updates' = bucket moves only, NOT true dist[] improvements."
    echo "│      All others count every dist[v] improvement. Not directly comparable."
    echo "└─────────────────────────────────────────────────────────────────────"
    echo ""
done

# =====================================================================
# FINAL SUMMARY TABLE — Ratio vs BH (the key comparison)
# =====================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  SUMMARY: Speed Ratio vs Binary Heap (lower = faster)              ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
printf "  %-6s" "Impl"
for graph in "${GRAPHS[@]}"; do
    short="${graph#USA-road-t.}"
    printf " │ %8s" "${short}"
done
echo ""
printf "  ──────"
for graph in "${GRAPHS[@]}"; do
    printf "─┼──────────"
done
echo ""

for impl_spec in "${IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    printf "  %-6s" "${label}"
    for graph in "${GRAPHS[@]}"; do
        ratio=$(grep "^${graph},${label}," "${SUMMARY_CSV}" | head -1 | cut -d, -f10)
        if [ -n "${ratio}" ]; then
            printf " │ %8s" "${ratio}"
        else
            printf " │ %8s" "N/A"
        fi
    done
    echo ""
done

echo ""
echo "  Values < 1.0 = faster than BH.  Values > 1.0 = slower than BH."
echo ""

# =====================================================================
# MEMORY SUMMARY
# =====================================================================
if [ "${HAS_GTIME}" -eq 1 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║  MEMORY: Peak RSS (KB) — measured on first run of each             ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  %-6s" "Impl"
    for graph in "${GRAPHS[@]}"; do
        short="${graph#USA-road-t.}"
        printf " │ %10s" "${short}"
    done
    echo ""
    printf "  ──────"
    for graph in "${GRAPHS[@]}"; do
        printf "─┼────────────"
    done
    echo ""

    for impl_spec in "${IMPLS[@]}"; do
        IFS=':' read -r label tbin cbin <<< "${impl_spec}"
        printf "  %-6s" "${label}"
        for graph in "${GRAPHS[@]}"; do
            mem=$(grep "^${graph},${label}," "${SUMMARY_CSV}" | head -1 | cut -d, -f6)
            if [ -n "${mem}" ] && [ "${mem}" != "N/A" ]; then
                printf " │ %10s" "${mem}"
            else
                printf " │ %10s" "N/A"
            fi
        done
        echo ""
    done
    echo ""
fi

# =====================================================================
# FAIRNESS NOTES
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  FAIRNESS NOTES                                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  1. ALL implementations compiled with identical flags:"
echo "       g++ -std=c++17 -Wall -O3 -DNDEBUG"
echo ""
echo "  2. SCANS (v): Identical across all correct Dijkstra implementations"
echo "     (same vertices settled). Differences indicate algorithmic divergence"
echo "     (e.g., LIFO tie-breaking in bucket queues)."
echo ""
echo "  3. UPDATES (i) — CRITICAL FAIRNESS CAVEAT:"
echo "     • BH, 4H, FH, PH, Dial, R1, R2, OMBI: count every dist[v] improvement"
echo "     • SQ (Goldberg): counts BUCKET MOVES only (bckOld != bckNew)."
echo "       If new distance maps to same bucket, SQ does NOT count it."
echo "       SQ's 'i' value is therefore LOWER and NOT directly comparable."
echo ""
echo "  4. MEMORY: Peak RSS via GNU time. Includes graph storage (shared"
echo "     across all), so the delta between implementations shows the"
echo "     priority queue overhead."
echo ""
echo "  5. TIMING: ${RUNS} runs per (graph, impl) pair. Median reported to"
echo "     reduce variance from OS scheduling jitter."
echo ""
echo "  6. CORRECTNESS: MD5 of all source→distance checksums verified"
echo "     against Binary Heap reference. ✅ = exact match."
echo ""

# =====================================================================
# DONE
# =====================================================================
echo "═══════════════════════════════════════════════════════════════════════"
echo "  Output files:"
echo "    Raw data:     ${RAW_CSV}"
echo "    Summary:      ${SUMMARY_CSV}"
echo "    Memory:       ${MEMORY_CSV}"
echo "    Checksums:    ${CHECKSUM_CSV}"
echo "═══════════════════════════════════════════════════════════════════════"
