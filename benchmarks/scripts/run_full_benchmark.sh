#!/bin/bash
#
# run_full_benchmark.sh — Comprehensive FAIR benchmark: OMBI vs all baselines
#
# ═══════════════════════════════════════════════════════════════════════════
# WHAT THIS MEASURES (per graph × per implementation):
#   1. Wall-clock time (ms)        — N runs → median, mean, stddev, min, max, 95% CI
#   2. Vertex scans                — nodes settled per query
#   3. Relaxations / updates       — dist[] improvements (SQ caveat noted)
#   4. Peak RSS memory (KB)        — via /usr/bin/time -v
#   5. ns/scan                     — time ÷ scans (per-operation efficiency)
#   6. ns/relaxation               — time ÷ updates
#   7. Throughput                  — nodes/sec
#   8. Ratio vs BH                — speed relative to Binary Heap
#   9. Correctness                 — MD5 checksum vs BH reference
#
# GRAPH TYPES:
#   Part 1: DIMACS road networks   — real-world, power-law degree, hierarchical
#   Part 2: Synthetic grid graphs  — uniform degree-4, stress-tests bucket queues
#
# STATISTICAL RIGOR:
#   - 11 runs per (graph, impl) — drop min & max → 9 effective runs
#   - Reports: median, mean, stddev, min, max, 95% CI (t-distribution, df=8)
#   - Warmup: 1 untimed run before measurement runs
#
# FAIRNESS NOTES:
#   - SQ's "i" (cUpdates) = bucket moves only, NOT true dist[] improvements.
#     All others count every dist[v] improvement. Marked with (*).
#   - All implementations use identical: g++ -std=c++17 -Wall -O3 -DNDEBUG
#   - Same graph parser, same source files, same machine, sequential execution.
# ═══════════════════════════════════════════════════════════════════════════
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

TOTAL_RUNS=11       # Total runs (drop min & max → 9 effective)
WARMUP_RUNS=1       # Untimed warmup runs
T_CRIT_95_DF8=2.306 # t-critical value for 95% CI with df=8 (9 effective samples)

# --- Road network graphs ---
ROAD_GRAPHS=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
    # "USA-road-t.USA"   # Uncomment for full USA (23.9M nodes — very slow!)
)

# --- Grid graphs (generated if missing) ---
# Format: name:width:maxWeight:seed
GRID_SPECS=(
    "grid_100x100_w100:100:100:42"
    "grid_100x100_w100000:100:100000:42"
    "grid_316x316_w100:316:100:42"
    "grid_316x316_w100000:316:100000:42"
    "grid_1000x1000_w100:1000:100:42"
    "grid_1000x1000_w100000:1000:100000:42"
    "grid_3162x3162_w100:3162:100:42"
    "grid_3162x3162_w100000:3162:100000:42"
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
# BANNER
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║  OMBI — Comprehensive Fair Benchmark Suite                             ║"
echo "║  Road Networks + Grid Graphs · Full Statistics · Memory · Correctness  ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Project root:   ${PROJECT_ROOT}"
echo "  Data dir:       ${DATA_DIR}"
echo "  Runs:           ${TOTAL_RUNS} total (drop min/max → $((TOTAL_RUNS - 2)) effective)"
echo "  Warmup:         ${WARMUP_RUNS} untimed run(s)"
echo "  Confidence:     95% CI (t-distribution, df=$((TOTAL_RUNS - 2 - 1)))"
echo "  Date:           $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# =====================================================================
# VALIDATION
# =====================================================================
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
    echo "  Run 'make all' first."
    exit 1
fi
echo "  ✅ All binaries found"

if [ ! -d "${DATA_DIR}" ]; then
    echo "  ❌ DATA_DIR not found: ${DATA_DIR}"
    exit 1
fi
echo "  ✅ Data directory found"

HAS_GTIME=0
if /usr/bin/time --version 2>&1 | grep -q "GNU"; then
    HAS_GTIME=1
    echo "  ✅ GNU time available (memory measurement enabled)"
else
    echo "  ⚠️  GNU time not available — install with: sudo apt install time"
fi

# Check gen_grid for grid generation
if [ ! -f "${BIN_DIR}/gen_grid" ]; then
    echo "  ⚠️  bin/gen_grid not found — grid graphs must already exist in data/"
fi
echo ""

# =====================================================================
# GENERATE GRID GRAPHS (if missing)
# =====================================================================
echo "--- Checking grid graphs ---"
GRID_GRAPHS=()
for spec in "${GRID_SPECS[@]}"; do
    IFS=':' read -r gname width maxw seed <<< "${spec}"
    gr_file="${DATA_DIR}/${gname}.gr"
    ss_file="${DATA_DIR}/${gname}.ss"

    if [ -f "${gr_file}" ] && [ -f "${ss_file}" ]; then
        echo "  ✅ ${gname} (exists)"
        GRID_GRAPHS+=("${gname}")
    elif [ -f "${BIN_DIR}/gen_grid" ]; then
        echo "  🔨 Generating ${gname} (${width}×${width}, maxW=${maxw}, seed=${seed})..."
        "${BIN_DIR}/gen_grid" "${width}" "${maxw}" "${seed}" "${DATA_DIR}/${gname}"
        if [ -f "${gr_file}" ] && [ -f "${ss_file}" ]; then
            echo "     ✅ Generated"
            GRID_GRAPHS+=("${gname}")
        else
            echo "     ❌ Generation failed — skipping"
        fi
    else
        # Try copying from nexus3 if available
        NEXUS_GRID="/mnt/d/Projects/Practice/Research/nexus3/C_Lang/v27-dimacs"
        if [ -f "${NEXUS_GRID}/${gname}.gr" ] && [ -f "${NEXUS_GRID}/${gname}.ss" ]; then
            echo "  📋 Copying ${gname} from nexus3..."
            cp "${NEXUS_GRID}/${gname}.gr" "${DATA_DIR}/"
            cp "${NEXUS_GRID}/${gname}.ss" "${DATA_DIR}/"
            GRID_GRAPHS+=("${gname}")
            echo "     ✅ Copied"
        else
            echo "  ⏭️  ${gname} — not found, no gen_grid, skipping"
        fi
    fi
done
echo ""

# Combine all graphs
ALL_GRAPHS=()
for g in "${ROAD_GRAPHS[@]}"; do ALL_GRAPHS+=("road:${g}"); done
for g in "${GRID_GRAPHS[@]}"; do ALL_GRAPHS+=("grid:${g}"); done

mkdir -p "${RESULTS_DIR}"

# =====================================================================
# OUTPUT FILES
# =====================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RAW_CSV="${RESULTS_DIR}/full_raw_${TIMESTAMP}.csv"
STATS_CSV="${RESULTS_DIR}/full_stats_${TIMESTAMP}.csv"
MEMORY_CSV="${RESULTS_DIR}/full_memory_${TIMESTAMP}.csv"
CHECKSUM_CSV="${RESULTS_DIR}/full_checksums_${TIMESTAMP}.csv"

echo "graph,graph_type,impl,run,time_ms,scans,updates,peak_rss_kb" > "${RAW_CSV}"
echo "graph,graph_type,impl,median_ms,mean_ms,stddev_ms,min_ms,max_ms,ci95_low,ci95_high,avg_scans,avg_updates,peak_rss_kb,ns_per_scan,ns_per_update,throughput_nodes_per_sec,ratio_vs_bh,checksum_ok" > "${STATS_CSV}"
echo "graph,graph_type,impl,peak_rss_kb" > "${MEMORY_CSV}"
echo "graph,graph_type,impl,checksum_md5,match_bh" > "${CHECKSUM_CSV}"

# =====================================================================
# STATISTICS HELPERS (pure bash + awk)
# =====================================================================

# Sort an array of floats and print space-separated
sort_floats() {
    local -a arr=("$@")
    printf '%s\n' "${arr[@]}" | sort -g | tr '\n' ' '
    echo ""
}

# Compute stats on an array of floats (after dropping min & max)
# Returns: median mean stddev min max ci95_low ci95_high effective_n
compute_stats() {
    local -a raw_vals=("$@")
    # Sort
    local sorted
    sorted=$(printf '%s\n' "${raw_vals[@]}" | sort -g)
    local -a vals
    mapfile -t vals <<< "${sorted}"
    local n=${#vals[@]}

    if [ "${n}" -lt 3 ]; then
        # Not enough to drop min/max — use all
        echo "${vals[0]} ${vals[0]} 0 ${vals[0]} ${vals[$((n-1))]} ${vals[0]} ${vals[$((n-1))]} ${n}" | awk '{printf "%s %s %s %s %s %s %s %s", $1,$2,$3,$4,$5,$6,$7,$8}'
        return
    fi

    # Drop min (index 0) and max (index n-1) → trimmed array
    local -a trimmed=("${vals[@]:1:$((n-2))}")
    local tn=${#trimmed[@]}

    # Pass to awk for all calculations
    printf '%s\n' "${trimmed[@]}" | awk -v tn="${tn}" -v t_crit="${T_CRIT_95_DF8}" \
        -v raw_min="${vals[0]}" -v raw_max="${vals[$((n-1))]}" '
    BEGIN { sum=0; sum2=0; idx=0 }
    {
        v[idx] = $1
        sum += $1
        sum2 += $1 * $1
        idx++
    }
    END {
        mean = sum / tn
        if (tn > 1) {
            variance = (sum2 - sum*sum/tn) / (tn - 1)
            if (variance < 0) variance = 0
            stddev = sqrt(variance)
        } else {
            stddev = 0
        }

        # Median of trimmed array
        if (tn % 2 == 1)
            median = v[int(tn/2)]
        else
            median = (v[tn/2 - 1] + v[tn/2]) / 2.0

        # 95% CI
        se = stddev / sqrt(tn)
        ci_low  = mean - t_crit * se
        ci_high = mean + t_crit * se

        printf "%.6f %.6f %.6f %.6f %.6f %.6f %.6f %d", median, mean, stddev, raw_min, raw_max, ci_low, ci_high, tn
    }'
}

# =====================================================================
# RUN ONE GRAPH SET
# =====================================================================
declare -A BH_MEDIAN  # BH median per graph for ratio calculation

run_benchmark_set() {
    local graph_type="$1"
    local graph="$2"
    local short="$3"

    local gr_file="${DATA_DIR}/${graph}.gr"
    local ss_file="${DATA_DIR}/${graph}.ss"

    if [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ]; then
        echo "  ⚠️  SKIP: ${graph} (missing .gr or .ss)"
        return
    fi

    echo "┌───────────────────────────────────────────────────────────────────────────────"
    echo "│  ${graph_type^^}: ${short}"
    echo "├───────────────────────────────────────────────────────────────────────────────"
    printf "│  %-6s │ %10s │ %8s │ %8s │ %8s │ %10s │ %10s │ %10s │ %8s │ %s\n" \
           "Impl" "Median(ms)" "Mean" "StdDev" "95%CI±" "Scans" "Updates" "RSS(KB)" "vs BH" "✓"
    echo "│  ───────┼────────────┼──────────┼──────────┼──────────┼────────────┼────────────┼────────────┼──────────┼───"

    local ref_checksum=""

    for impl_spec in "${IMPLS[@]}"; do
        IFS=':' read -r label tbin cbin <<< "${impl_spec}"

        # --- Warmup run (untimed, not recorded) ---
        for _w in $(seq 1 ${WARMUP_RUNS}); do
            local warmup_file="${RESULTS_DIR}/.tmp_warmup.txt"
            rm -f "${warmup_file}"
            "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${warmup_file}" 2>/dev/null || true
            rm -f "${warmup_file}"
        done

        # --- Measurement runs ---
        local -a times=()
        local last_scans="0"
        local last_updates="0"
        local rss_kb="N/A"

        for run in $(seq 1 ${TOTAL_RUNS}); do
            local out_file="${RESULTS_DIR}/.tmp_${label}_${short}_run${run}.txt"
            rm -f "${out_file}"

            # Measure memory on first run only
            if [ "${HAS_GTIME}" -eq 1 ] && [ "${run}" -eq 1 ]; then
                local time_out
                time_out=$(/usr/bin/time -v "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${out_file}" 2>&1 || true)
                local rss_line
                rss_line=$(echo "${time_out}" | grep "Maximum resident set size" || true)
                if [ -n "${rss_line}" ]; then
                    rss_kb=$(echo "${rss_line}" | awk '{print $NF}')
                fi
            else
                "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${out_file}" 2>/dev/null || true
            fi

            local t_ms scans updates
            t_ms=$(grep '^t ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "0")
            scans=$(grep '^v ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "0")
            updates=$(grep '^i ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "0")

            times+=("${t_ms}")
            last_scans="${scans}"
            last_updates="${updates}"

            echo "${graph},${graph_type},${label},${run},${t_ms},${scans},${updates},${rss_kb}" >> "${RAW_CSV}"
            rm -f "${out_file}"
        done

        # --- Compute statistics ---
        local stats_str
        stats_str=$(compute_stats "${times[@]}")
        local median_ms mean_ms stddev_ms min_ms max_ms ci95_low ci95_high eff_n
        read -r median_ms mean_ms stddev_ms min_ms max_ms ci95_low ci95_high eff_n <<< "${stats_str}"

        # CI half-width for display
        local ci_half
        ci_half=$(echo "${ci95_high} ${ci95_low}" | awk '{printf "%.3f", ($1 - $2) / 2.0}')

        # --- Checksum verification ---
        local cout_file="${RESULTS_DIR}/.tmp_${label}_${short}_chk.txt"
        rm -f "${cout_file}"
        "${BIN_DIR}/${cbin}" "${gr_file}" "${ss_file}" "${cout_file}" 2>/dev/null || true
        local chk_md5
        chk_md5=$(grep '^d ' "${cout_file}" 2>/dev/null | md5sum | awk '{print $1}')
        rm -f "${cout_file}"

        if [ "${label}" = "bh" ]; then
            ref_checksum="${chk_md5}"
        fi

        local match match_csv
        if [ "${chk_md5}" = "${ref_checksum}" ]; then
            match="✅"
            match_csv="YES"
        else
            match="❌"
            match_csv="NO"
        fi

        # --- Derived metrics ---
        local ns_per_scan="N/A" ns_per_update="N/A" throughput="N/A"
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
        local ratio="N/A"
        local bh_med="${BH_MEDIAN[${graph}]:-}"
        if [ -n "${bh_med}" ] && [ "${bh_med}" != "0" ]; then
            ratio=$(echo "${median_ms} ${bh_med}" | awk '{printf "%.3f", $1 / $2}')
        fi

        # --- Print row ---
        local updates_display="${last_updates}"
        if [ "${label}" = "sq" ]; then
            updates_display="${last_updates}(*)"
        fi

        printf "│  %-6s │ %10s │ %8s │ %8s │ %8s │ %10s │ %10s │ %10s │ %8s │ %s\n" \
               "${label}" \
               "$(echo "${median_ms}" | awk '{printf "%.3f", $1}')" \
               "$(echo "${mean_ms}" | awk '{printf "%.3f", $1}')" \
               "$(echo "${stddev_ms}" | awk '{printf "%.3f", $1}')" \
               "±${ci_half}" \
               "${last_scans}" \
               "${updates_display}" \
               "${rss_kb}" \
               "${ratio}" \
               "${match}"

        # --- Write to CSVs ---
        echo "${graph},${graph_type},${label},${median_ms},${mean_ms},${stddev_ms},${min_ms},${max_ms},${ci95_low},${ci95_high},${last_scans},${last_updates},${rss_kb},${ns_per_scan},${ns_per_update},${throughput},${ratio},${match_csv}" >> "${STATS_CSV}"
        echo "${graph},${graph_type},${label},${chk_md5},${match_csv}" >> "${CHECKSUM_CSV}"
        if [ "${rss_kb}" != "N/A" ]; then
            echo "${graph},${graph_type},${label},${rss_kb}" >> "${MEMORY_CSV}"
        fi
    done

    echo "│"
    echo "│  Runs: ${TOTAL_RUNS} total, drop min/max → $((TOTAL_RUNS-2)) effective. 95% CI shown."
    if echo "${IMPLS[@]}" | grep -q "sq:"; then
        echo "│  (*) SQ 'updates' = bucket moves only, NOT true dist[] improvements."
    fi
    echo "└───────────────────────────────────────────────────────────────────────────────"
    echo ""
}

# =====================================================================
# PART 1: ROAD NETWORKS
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  PART 1: DIMACS Road Networks                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

for graph in "${ROAD_GRAPHS[@]}"; do
    short="${graph#USA-road-t.}"
    run_benchmark_set "road" "${graph}" "${short}"
done

# =====================================================================
# PART 2: GRID GRAPHS
# =====================================================================
if [ ${#GRID_GRAPHS[@]} -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  PART 2: Synthetic Grid Graphs                                             ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    for graph in "${GRID_GRAPHS[@]}"; do
        run_benchmark_set "grid" "${graph}" "${graph}"
    done
fi

# =====================================================================
# SUMMARY TABLE — Speed Ratio vs BH (Road Networks)
# =====================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SUMMARY: Speed Ratio vs Binary Heap — Road Networks (lower = faster)      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
printf "  %-6s" "Impl"
for graph in "${ROAD_GRAPHS[@]}"; do
    short="${graph#USA-road-t.}"
    printf " │ %8s" "${short}"
done
echo ""
printf "  ──────"
for graph in "${ROAD_GRAPHS[@]}"; do
    printf "─┼──────────"
done
echo ""

for impl_spec in "${IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    printf "  %-6s" "${label}"
    for graph in "${ROAD_GRAPHS[@]}"; do
        ratio=$(grep "^${graph},road,${label}," "${STATS_CSV}" | head -1 | cut -d, -f17)
        if [ -n "${ratio}" ]; then
            printf " │ %8s" "${ratio}"
        else
            printf " │ %8s" "N/A"
        fi
    done
    echo ""
done
echo ""
echo "  < 1.000 = faster than BH    > 1.000 = slower than BH"

# =====================================================================
# SUMMARY TABLE — Speed Ratio vs BH (Grid Graphs)
# =====================================================================
if [ ${#GRID_GRAPHS[@]} -gt 0 ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SUMMARY: Speed Ratio vs Binary Heap — Grid Graphs (lower = faster)        ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Group by weight range for readability
    for wlabel in "w100" "w100000"; do
        echo "  --- Weight range: ${wlabel} ---"
        printf "  %-6s" "Impl"
        local_grids=()
        for graph in "${GRID_GRAPHS[@]}"; do
            if echo "${graph}" | grep -q "${wlabel}"; then
                local_grids+=("${graph}")
                short="${graph%%_${wlabel}}"
                short="${short#grid_}"
                printf " │ %12s" "${short}"
            fi
        done
        echo ""
        printf "  ──────"
        for _ in "${local_grids[@]}"; do
            printf "─┼──────────────"
        done
        echo ""

        for impl_spec in "${IMPLS[@]}"; do
            IFS=':' read -r label tbin cbin <<< "${impl_spec}"
            printf "  %-6s" "${label}"
            for graph in "${local_grids[@]}"; do
                ratio=$(grep "^${graph},grid,${label}," "${STATS_CSV}" | head -1 | cut -d, -f17)
                if [ -n "${ratio}" ]; then
                    printf " │ %12s" "${ratio}"
                else
                    printf " │ %12s" "N/A"
                fi
            done
            echo ""
        done
        echo ""
    done
fi

# =====================================================================
# MEMORY SUMMARY
# =====================================================================
if [ "${HAS_GTIME}" -eq 1 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  MEMORY: Peak RSS (KB) — Road Networks                                     ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  %-6s" "Impl"
    for graph in "${ROAD_GRAPHS[@]}"; do
        short="${graph#USA-road-t.}"
        printf " │ %10s" "${short}"
    done
    echo ""
    printf "  ──────"
    for graph in "${ROAD_GRAPHS[@]}"; do
        printf "─┼────────────"
    done
    echo ""

    for impl_spec in "${IMPLS[@]}"; do
        IFS=':' read -r label tbin cbin <<< "${impl_spec}"
        printf "  %-6s" "${label}"
        for graph in "${ROAD_GRAPHS[@]}"; do
            mem=$(grep "^${graph},road,${label}," "${STATS_CSV}" | head -1 | cut -d, -f13)
            if [ -n "${mem}" ] && [ "${mem}" != "N/A" ]; then
                printf " │ %10s" "${mem}"
            else
                printf " │ %10s" "N/A"
            fi
        done
        echo ""
    done
    echo ""

    # Memory for grids
    if [ ${#GRID_GRAPHS[@]} -gt 0 ]; then
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║  MEMORY: Peak RSS (KB) — Grid Graphs                                       ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        for wlabel in "w100" "w100000"; do
            echo "  --- Weight range: ${wlabel} ---"
            printf "  %-6s" "Impl"
            local_grids=()
            for graph in "${GRID_GRAPHS[@]}"; do
                if echo "${graph}" | grep -q "${wlabel}"; then
                    local_grids+=("${graph}")
                    short="${graph%%_${wlabel}}"
                    short="${short#grid_}"
                    printf " │ %12s" "${short}"
                fi
            done
            echo ""
            printf "  ──────"
            for _ in "${local_grids[@]}"; do
                printf "─┼──────────────"
            done
            echo ""

            for impl_spec in "${IMPLS[@]}"; do
                IFS=':' read -r label tbin cbin <<< "${impl_spec}"
                printf "  %-6s" "${label}"
                for graph in "${local_grids[@]}"; do
                    mem=$(grep "^${graph},grid,${label}," "${STATS_CSV}" | head -1 | cut -d, -f13)
                    if [ -n "${mem}" ] && [ "${mem}" != "N/A" ]; then
                        printf " │ %12s" "${mem}"
                    else
                        printf " │ %12s" "N/A"
                    fi
                done
                echo ""
            done
            echo ""
        done
    fi
fi

# =====================================================================
# STATISTICAL DETAIL TABLE
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  STATISTICAL DETAIL: Timing Distribution (all graphs)                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
printf "  %-20s %-6s │ %10s │ %10s │ %10s │ %10s │ %10s │ %16s\n" \
       "Graph" "Impl" "Median" "Mean" "StdDev" "Min" "Max" "95% CI"
echo "  ─────────────────── ───────┼────────────┼────────────┼────────────┼────────────┼────────────┼──────────────────"

# Read stats CSV and print
tail -n +2 "${STATS_CSV}" | while IFS=, read -r graph gtype impl median mean stddev min_v max_v ci_low ci_high scans updates rss ns_s ns_u tput ratio chk; do
    short="${graph#USA-road-t.}"
    ci_str="[$(echo "${ci_low}" | awk '{printf "%.3f",$1}'), $(echo "${ci_high}" | awk '{printf "%.3f",$1}')]"
    printf "  %-20s %-6s │ %10s │ %10s │ %10s │ %10s │ %10s │ %16s\n" \
           "${short}" "${impl}" \
           "$(echo "${median}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${mean}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${stddev}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${min_v}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${max_v}" | awk '{printf "%.3f",$1}')" \
           "${ci_str}"
done
echo ""

# =====================================================================
# FAIRNESS NOTES
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  FAIRNESS & METHODOLOGY NOTES                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  COMPILER:    All implementations: g++ -std=c++17 -Wall -O3 -DNDEBUG"
echo "  TIMING:      ${TOTAL_RUNS} runs, drop min & max → $((TOTAL_RUNS-2)) effective."
echo "               1 warmup run (untimed) before measurement."
echo "  STATISTICS:  Median (primary), mean, stddev, min, max, 95% CI."
echo "               CI uses t-distribution (df=$((TOTAL_RUNS-2-1)), t=${T_CRIT_95_DF8})."
echo ""
echo "  SCANS (v):   Nodes dequeued & settled. Should be identical across all"
echo "               correct Dijkstra variants. Small differences indicate"
echo "               tie-breaking divergence (LIFO in bucket queues vs FIFO in heaps)."
echo ""
echo "  UPDATES (i): ⚠️  CRITICAL FAIRNESS CAVEAT:"
echo "    • BH, 4H, FH, PH, Dial, R1, R2, OMBI: count every dist[v] improvement."
echo "    • SQ (Goldberg): counts BUCKET MOVES only (bckOld != bckNew)."
echo "      If new distance maps to same bucket, SQ does NOT count it."
echo "      SQ's 'i' value is therefore LOWER and NOT directly comparable."
echo "      Marked with (*) in all tables."
echo ""
echo "  MEMORY:      Peak RSS via GNU /usr/bin/time -v. Includes graph storage"
echo "               (shared overhead). Delta between implementations = PQ overhead."
echo ""
echo "  GRAPHS:"
echo "    Road:  Real DIMACS 9th Challenge road networks (power-law degree,"
echo "           hierarchical structure, natural clustering)."
echo "    Grid:  Synthetic W×W grids, uniform degree-4, random weights."
echo "           Tests whether bucket queue advantages persist on non-hierarchical"
echo "           topologies. Two weight ranges:"
echo "             w100    — narrow range [1,100] → many bucket collisions"
echo "             w100000 — wide range [1,100000] → spread across buckets"
echo ""
echo "  CORRECTNESS: MD5 of all source→distance checksums verified against"
echo "               Binary Heap reference. ✅ = exact match."
echo ""

# =====================================================================
# DONE
# =====================================================================
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Output files:"
echo "    Raw data:     ${RAW_CSV}"
echo "    Statistics:   ${STATS_CSV}"
echo "    Memory:       ${MEMORY_CSV}"
echo "    Checksums:    ${CHECKSUM_CSV}"
echo ""
echo "  CSV columns in ${STATS_CSV}:"
echo "    graph, graph_type, impl, median_ms, mean_ms, stddev_ms, min_ms, max_ms,"
echo "    ci95_low, ci95_high, avg_scans, avg_updates, peak_rss_kb, ns_per_scan,"
echo "    ns_per_update, throughput_nodes_per_sec, ratio_vs_bh, checksum_ok"
echo "═══════════════════════════════════════════════════════════════════════════════"
