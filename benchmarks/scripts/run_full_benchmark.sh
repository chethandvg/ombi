#!/bin/bash
#
# run_full_benchmark.sh — Comprehensive FAIR benchmark: OMBI vs all baselines
#
# ═══════════════════════════════════════════════════════════════════════════════
# WHAT THIS MEASURES (per graph × per implementation):
#
#   PERFORMANCE:
#     1. Wall-clock time (ms)     — N runs → median, mean, stddev, min, max, 95% CI
#     2. Vertex scans             — nodes settled per query
#     3. Relaxations / updates    — dist[] improvements (SQ caveat noted)
#     4. ns/scan                  — time ÷ scans
#     5. ns/relaxation            — time ÷ updates
#     6. Throughput               — nodes/sec
#     7. Ratio vs BH              — speed relative to Binary Heap
#
#   RESOURCE:
#     8. Peak RSS memory (KB)     — via /usr/bin/time -v
#     9. Binary size (bytes)      — stat on each executable
#    10. Compilation time (s)     — timed make for each target
#
#   CORRECTNESS:
#    11. MD5 checksum             — vs BH reference
#
#   ANALYSIS:
#    12. Scalability analysis     — regression of time vs graph size
#    13. OMBI variant comparison  — base, opt, v2 (caliber/F-set)
#    14. BW_MULT sensitivity      — bw = {1,2,3,4,6,8} × minArcLen
#    15. HOT_BUCKETS sweep        — 2^10 .. 2^18
#    16. CH integration           — Contraction Hierarchies (preprocessing + query)
#
#   GRAPH TYPES:
#     Part 1: DIMACS road networks  — real-world, power-law, hierarchical
#     Part 2: Synthetic grid graphs — uniform degree-4, two weight ranges
#
#   STATISTICAL RIGOR:
#     - 11 runs per (graph, impl) — drop min & max → 9 effective
#     - Reports: median, mean, stddev, min, max, 95% CI (t-dist, df=8)
#     - 1 warmup run (untimed) before measurement
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   cd /mnt/d/Projects/Practice/Research/ombi
#   make all && make sweep-bw && make sweep-hot
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
EFF_RUNS=$((TOTAL_RUNS - 2))
T_CRIT_95_DF8=2.306 # t-critical for 95% CI with df=8

# --- Road network graphs ---
ROAD_GRAPHS=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
    # "USA-road-t.USA"   # Uncomment for full USA (23.9M nodes — very slow!)
)

# --- Grid graph specs: name:width:maxWeight:seed ---
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

# --- Core implementations ---
CORE_IMPLS=(
    "bh:dij_bh:dij_bhC"
    "4h:dij_4h:dij_4hC"
    "fh:dij_fh:dij_fhC"
    "ph:dij_ph:dij_phC"
    "dial:dij_dial:dij_dialC"
    "r1:dij_r1:dij_r1C"
    "r2:dij_r2:dij_r2C"
    "ombi:ombi:ombiC"
    "sq:sq:sqC"
    "ch:dij_ch:dij_chC"
)

# --- OMBI variants ---
VARIANT_IMPLS=(
    "ombi:ombi:ombiC"
    "ombi_opt:ombi_opt:ombi_optC"
    "ombi_v2:ombi_v2:ombi_v2C"
)

# --- BW_MULT sweep ---
BW_VALS=(1 2 3 4 6 8)

# --- HOT_BUCKETS sweep (exponents) ---
HOT_EXPS=(10 11 12 13 14 15 16 17 18)

# =====================================================================
# BANNER
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  OMBI — Comprehensive Fair Benchmark Suite v2                              ║"
echo "║  Road + Grid · Stats · Memory · Variants · Sweeps · CH · Scalability       ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Project root:   ${PROJECT_ROOT}"
echo "  Data dir:       ${DATA_DIR}"
echo "  Runs:           ${TOTAL_RUNS} total → drop min/max → ${EFF_RUNS} effective"
echo "  Warmup:         ${WARMUP_RUNS} untimed run(s)"
echo "  Confidence:     95% CI (t-distribution, df=$((EFF_RUNS-1)), t=${T_CRIT_95_DF8})"
echo "  Date:           $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# =====================================================================
# VALIDATION
# =====================================================================
echo "--- Checking binaries ---"
warn_missing() {
    echo "  ⚠️  Missing: bin/$1 (will skip)"
}

# Core impls — required
core_ok=1
for impl_spec in "${CORE_IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    for b in "${tbin}" "${cbin}"; do
        if [ ! -f "${BIN_DIR}/${b}" ]; then
            if [ "${label}" = "ch" ]; then
                warn_missing "${b}"
            else
                echo "  ❌ Missing: bin/${b}"
                core_ok=0
            fi
        fi
    done
done
if [ "${core_ok}" -eq 0 ]; then
    echo "  Run 'make all' first."
    exit 1
fi
echo "  ✅ Core binaries found"

# Variant impls — optional
for impl_spec in "${VARIANT_IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    if [ ! -f "${BIN_DIR}/${tbin}" ]; then
        warn_missing "${tbin}"
    fi
done

# BW sweep — optional
bw_available=0
for bw in "${BW_VALS[@]}"; do
    if [ -f "${BIN_DIR}/ombi_bw${bw}" ]; then
        bw_available=$((bw_available + 1))
    fi
done
if [ "${bw_available}" -gt 0 ]; then
    echo "  ✅ BW_MULT sweep binaries: ${bw_available}/${#BW_VALS[@]}"
else
    echo "  ⚠️  No BW sweep binaries — run 'make sweep-bw' to enable"
fi

# HOT sweep — optional
hot_available=0
for exp in "${HOT_EXPS[@]}"; do
    if [ -f "${BIN_DIR}/ombi_hot${exp}" ]; then
        hot_available=$((hot_available + 1))
    fi
done
if [ "${hot_available}" -gt 0 ]; then
    echo "  ✅ HOT_BUCKETS sweep binaries: ${hot_available}/${#HOT_EXPS[@]}"
else
    echo "  ⚠️  No HOT sweep binaries — run 'make sweep-hot' to enable"
fi

# Data directory
if [ ! -d "${DATA_DIR}" ]; then
    echo "  ❌ DATA_DIR not found: ${DATA_DIR}"
    exit 1
fi
echo "  ✅ Data directory found"

# GNU time
HAS_GTIME=0
if /usr/bin/time --version 2>&1 | grep -q "GNU"; then
    HAS_GTIME=1
    echo "  ✅ GNU time available (memory measurement enabled)"
else
    echo "  ⚠️  GNU time not available — install: sudo apt install time"
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
        echo "  ✅ ${gname}"
        GRID_GRAPHS+=("${gname}")
    elif [ -f "${BIN_DIR}/gen_grid" ]; then
        echo "  🔨 Generating ${gname} (${width}×${width}, maxW=${maxw})..."
        "${BIN_DIR}/gen_grid" "${width}" "${maxw}" "${seed}" "${DATA_DIR}/${gname}"
        if [ -f "${gr_file}" ] && [ -f "${ss_file}" ]; then
            GRID_GRAPHS+=("${gname}")
        else
            echo "     ❌ Failed — skipping"
        fi
    else
        NEXUS_GRID="/mnt/d/Projects/Practice/Research/nexus3/C_Lang/v27-dimacs"
        if [ -f "${NEXUS_GRID}/${gname}.gr" ] && [ -f "${NEXUS_GRID}/${gname}.ss" ]; then
            echo "  📋 Copying ${gname} from nexus3..."
            cp "${NEXUS_GRID}/${gname}.gr" "${DATA_DIR}/"
            cp "${NEXUS_GRID}/${gname}.ss" "${DATA_DIR}/"
            GRID_GRAPHS+=("${gname}")
        else
            echo "  ⏭️  ${gname} — skipping"
        fi
    fi
done
echo ""

mkdir -p "${RESULTS_DIR}"

# =====================================================================
# OUTPUT FILES
# =====================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RAW_CSV="${RESULTS_DIR}/full_raw_${TIMESTAMP}.csv"
STATS_CSV="${RESULTS_DIR}/full_stats_${TIMESTAMP}.csv"
MEMORY_CSV="${RESULTS_DIR}/full_memory_${TIMESTAMP}.csv"
CHECKSUM_CSV="${RESULTS_DIR}/full_checksums_${TIMESTAMP}.csv"
BUILD_CSV="${RESULTS_DIR}/full_build_${TIMESTAMP}.csv"
SCALABILITY_CSV="${RESULTS_DIR}/full_scalability_${TIMESTAMP}.csv"
VARIANT_CSV="${RESULTS_DIR}/full_variants_${TIMESTAMP}.csv"
BW_CSV="${RESULTS_DIR}/full_bw_sweep_${TIMESTAMP}.csv"
HOT_CSV="${RESULTS_DIR}/full_hot_sweep_${TIMESTAMP}.csv"

echo "graph,graph_type,impl,run,time_ms,scans,updates,peak_rss_kb" > "${RAW_CSV}"
echo "graph,graph_type,impl,median_ms,mean_ms,stddev_ms,min_ms,max_ms,ci95_low,ci95_high,avg_scans,avg_updates,peak_rss_kb,ns_per_scan,ns_per_update,throughput_nodes_per_sec,ratio_vs_bh,checksum_ok" > "${STATS_CSV}"
echo "graph,graph_type,impl,peak_rss_kb" > "${MEMORY_CSV}"
echo "graph,graph_type,impl,checksum_md5,match_bh" > "${CHECKSUM_CSV}"
echo "target,compile_time_sec,binary_size_bytes" > "${BUILD_CSV}"
echo "graph_type,impl,graph,nodes,median_ms,log_nodes,log_ms" > "${SCALABILITY_CSV}"
echo "graph,graph_type,variant,median_ms,mean_ms,stddev_ms,ci95_low,ci95_high,scans,updates,ratio_vs_base" > "${VARIANT_CSV}"
echo "graph,bw_mult,median_ms,mean_ms,stddev_ms,ci95_low,ci95_high,ratio_vs_bw4" > "${BW_CSV}"
echo "graph,hot_exp,hot_buckets,median_ms,mean_ms,stddev_ms,ci95_low,ci95_high,ratio_vs_14" > "${HOT_CSV}"

# =====================================================================
# STATISTICS HELPERS
# =====================================================================

# Compute stats on array of floats (drop min & max → trimmed)
# Output: median mean stddev min max ci95_low ci95_high
compute_stats() {
    local -a raw_vals=("$@")
    local sorted
    sorted=$(printf '%s\n' "${raw_vals[@]}" | sort -g)
    local -a vals
    mapfile -t vals <<< "${sorted}"
    local n=${#vals[@]}

    if [ "${n}" -lt 3 ]; then
        printf '%s\n' "${raw_vals[@]}" | awk -v t="${T_CRIT_95_DF8}" '
        BEGIN { sum=0; idx=0 }
        { v[idx]=$1; sum+=$1; idx++ }
        END {
            mean=sum/idx; median=v[int(idx/2)];
            printf "%.6f %.6f 0.000000 %.6f %.6f %.6f %.6f", median,mean,v[0],v[idx-1],mean,mean
        }'
        return
    fi

    # Drop min (index 0) and max (index n-1)
    local -a trimmed=("${vals[@]:1:$((n-2))}")

    printf '%s\n' "${trimmed[@]}" | awk -v tn="${#trimmed[@]}" -v t="${T_CRIT_95_DF8}" \
        -v raw_min="${vals[0]}" -v raw_max="${vals[$((n-1))]}" '
    BEGIN { sum=0; sum2=0; idx=0 }
    {
        v[idx]=$1; sum+=$1; sum2+=$1*$1; idx++
    }
    END {
        mean = sum/tn
        if (tn>1) { var=(sum2-sum*sum/tn)/(tn-1); if(var<0)var=0; sd=sqrt(var) }
        else { sd=0 }
        if (tn%2==1) median=v[int(tn/2)]
        else median=(v[tn/2-1]+v[tn/2])/2.0
        se=sd/sqrt(tn)
        printf "%.6f %.6f %.6f %.6f %.6f %.6f %.6f", median,mean,sd,raw_min,raw_max,mean-t*se,mean+t*se
    }'
}

# Get node count from .gr file header
get_node_count() {
    grep '^p sp' "$1" | head -1 | awk '{print $3}'
}

# =====================================================================
# SECTION 0: COMPILATION TIME & BINARY SIZE
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SECTION 0: Compilation Time & Binary Size                                 ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Clean and rebuild each target, timing each
MAKE_TARGETS=(
    "ombi:bin/ombi"
    "ombi_opt:bin/ombi_opt"
    "ombi_v2:bin/ombi_v2"
    "dij_bh:bin/dij_bh"
    "dij_4h:bin/dij_4h"
    "dij_fh:bin/dij_fh"
    "dij_ph:bin/dij_ph"
    "dij_dial:bin/dij_dial"
    "dij_r1:bin/dij_r1"
    "dij_r2:bin/dij_r2"
    "dij_ch:bin/dij_ch"
    "sq:bin/sq"
)

printf "  %-14s │ %12s │ %14s\n" "Target" "Compile(s)" "Binary(bytes)"
echo "  ────────────── ┼ ──────────────┼ ───────────────"

for mt in "${MAKE_TARGETS[@]}"; do
    IFS=':' read -r tlabel tpath <<< "${mt}"
    rm -f "${PROJECT_ROOT}/${tpath}" 2>/dev/null || true

    t_start=$(date +%s%N)
    make -C "${PROJECT_ROOT}" "${tpath}" -j1 > /dev/null 2>&1 || true
    t_end=$(date +%s%N)

    compile_sec=$(echo "${t_start} ${t_end}" | awk '{printf "%.3f", ($2-$1)/1000000000.0}')

    bin_size="N/A"
    if [ -f "${PROJECT_ROOT}/${tpath}" ]; then
        bin_size=$(stat -c%s "${PROJECT_ROOT}/${tpath}" 2>/dev/null || echo "N/A")
    fi

    printf "  %-14s │ %12s │ %14s\n" "${tlabel}" "${compile_sec}" "${bin_size}"
    echo "${tlabel},${compile_sec},${bin_size}" >> "${BUILD_CSV}"
done
echo ""

# Rebuild everything cleanly for the actual benchmark
echo "  Rebuilding all binaries for benchmark..."
make -C "${PROJECT_ROOT}" clean > /dev/null 2>&1 || true
make -C "${PROJECT_ROOT}" all -j$(nproc) > /dev/null 2>&1 || true

# Build sweeps if targets exist in Makefile
if [ "${bw_available}" -eq 0 ]; then
    echo "  Building BW sweep binaries..."
    make -C "${PROJECT_ROOT}" sweep-bw > /dev/null 2>&1 || true
fi
if [ "${hot_available}" -eq 0 ]; then
    echo "  Building HOT_BUCKETS sweep binaries..."
    make -C "${PROJECT_ROOT}" sweep-hot > /dev/null 2>&1 || true
fi

# Re-check sweep availability after build
bw_available=0
for bw in "${BW_VALS[@]}"; do
    [ -f "${BIN_DIR}/ombi_bw${bw}" ] && bw_available=$((bw_available + 1))
done
hot_available=0
for exp in "${HOT_EXPS[@]}"; do
    [ -f "${BIN_DIR}/ombi_hot${exp}" ] && hot_available=$((hot_available + 1))
done

echo ""

# =====================================================================
# CORE BENCHMARK FUNCTION
# =====================================================================
declare -A BH_MEDIAN

run_impl_benchmark() {
    local graph_type="$1"
    local graph="$2"
    local short="$3"
    local impl_spec="$4"
    local csv_file="$5"      # which CSV to append stats to

    IFS=':' read -r label tbin cbin <<< "${impl_spec}"

    # Skip if binary missing
    if [ ! -f "${BIN_DIR}/${tbin}" ] || [ ! -f "${BIN_DIR}/${cbin}" ]; then
        return 1
    fi

    local gr_file="${DATA_DIR}/${graph}.gr"
    local ss_file="${DATA_DIR}/${graph}.ss"

    # Warmup
    for _w in $(seq 1 ${WARMUP_RUNS}); do
        local wf="${RESULTS_DIR}/.tmp_warmup.txt"
        rm -f "${wf}"
        "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${wf}" 2>/dev/null || true
        rm -f "${wf}"
    done

    # Measurement runs
    local -a times=()
    local last_scans="0" last_updates="0" rss_kb="N/A"

    for run in $(seq 1 ${TOTAL_RUNS}); do
        local out_file="${RESULTS_DIR}/.tmp_${label}_${short}_r${run}.txt"
        rm -f "${out_file}"

        if [ "${HAS_GTIME}" -eq 1 ] && [ "${run}" -eq 1 ]; then
            local time_out
            time_out=$(/usr/bin/time -v "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${out_file}" 2>&1 || true)
            local rss_line
            rss_line=$(echo "${time_out}" | grep "Maximum resident set size" || true)
            [ -n "${rss_line}" ] && rss_kb=$(echo "${rss_line}" | awk '{print $NF}')
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

    # Statistics
    local stats_str
    stats_str=$(compute_stats "${times[@]}")
    local median_ms mean_ms stddev_ms min_ms max_ms ci95_low ci95_high
    read -r median_ms mean_ms stddev_ms min_ms max_ms ci95_low ci95_high <<< "${stats_str}"

    local ci_half
    ci_half=$(echo "${ci95_high} ${ci95_low}" | awk '{printf "%.3f", ($1-$2)/2.0}')

    # Checksum
    local cout_file="${RESULTS_DIR}/.tmp_${label}_${short}_chk.txt"
    rm -f "${cout_file}"
    "${BIN_DIR}/${cbin}" "${gr_file}" "${ss_file}" "${cout_file}" 2>/dev/null || true
    local chk_md5
    chk_md5=$(grep '^d ' "${cout_file}" 2>/dev/null | md5sum | awk '{print $1}')
    rm -f "${cout_file}"

    if [ "${label}" = "bh" ]; then
        BH_REF_CHECKSUM="${chk_md5}"
    fi

    local match_csv="YES"
    local match="✅"
    if [ "${chk_md5}" != "${BH_REF_CHECKSUM:-}" ]; then
        match="❌"; match_csv="NO"
    fi

    # Derived metrics
    local ns_per_scan="N/A" ns_per_update="N/A" throughput="N/A"
    if [ "${last_scans}" != "0" ] && [ "${last_scans}" != "N/A" ]; then
        ns_per_scan=$(echo "${median_ms} ${last_scans}" | awk '{printf "%.1f", ($1*1e6)/$2}')
        throughput=$(echo "${median_ms} ${last_scans}" | awk '{printf "%.0f", ($2*1000.0)/$1}')
    fi
    [ "${last_updates}" != "0" ] && [ "${last_updates}" != "N/A" ] && \
        ns_per_update=$(echo "${median_ms} ${last_updates}" | awk '{printf "%.1f", ($1*1e6)/$2}')

    # Store BH median
    [ "${label}" = "bh" ] && BH_MEDIAN["${graph}"]="${median_ms}"

    # Ratio vs BH
    local ratio="N/A"
    local bh_med="${BH_MEDIAN[${graph}]:-}"
    [ -n "${bh_med}" ] && [ "${bh_med}" != "0" ] && \
        ratio=$(echo "${median_ms} ${bh_med}" | awk '{printf "%.3f", $1/$2}')

    # Display
    local upd_disp="${last_updates}"
    [ "${label}" = "sq" ] && upd_disp="${last_updates}(*)"

    printf "│  %-10s │ %10s │ %8s │ %8s │ %8s │ %10s │ %10s │ %10s │ %8s │ %s\n" \
           "${label}" \
           "$(echo "${median_ms}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${mean_ms}" | awk '{printf "%.3f",$1}')" \
           "$(echo "${stddev_ms}" | awk '{printf "%.4f",$1}')" \
           "±${ci_half}" \
           "${last_scans}" \
           "${upd_disp}" \
           "${rss_kb}" \
           "${ratio}" \
           "${match}"

    # Write to stats CSV
    echo "${graph},${graph_type},${label},${median_ms},${mean_ms},${stddev_ms},${min_ms},${max_ms},${ci95_low},${ci95_high},${last_scans},${last_updates},${rss_kb},${ns_per_scan},${ns_per_update},${throughput},${ratio},${match_csv}" >> "${csv_file}"

    echo "${graph},${graph_type},${label},${chk_md5},${match_csv}" >> "${CHECKSUM_CSV}"
    [ "${rss_kb}" != "N/A" ] && echo "${graph},${graph_type},${label},${rss_kb}" >> "${MEMORY_CSV}"

    # Export for caller
    LAST_MEDIAN="${median_ms}"
    LAST_MEAN="${mean_ms}"
    LAST_STDDEV="${stddev_ms}"
    LAST_CI_LOW="${ci95_low}"
    LAST_CI_HIGH="${ci95_high}"
    LAST_SCANS="${last_scans}"
    LAST_UPDATES="${last_updates}"

    return 0
}

print_table_header() {
    printf "│  %-10s │ %10s │ %8s │ %8s │ %8s │ %10s │ %10s │ %10s │ %8s │ %s\n" \
           "Impl" "Median(ms)" "Mean" "StdDev" "95%CI±" "Scans" "Updates" "RSS(KB)" "vs BH" "✓"
    echo "│  ───────────┼────────────┼──────────┼──────────┼──────────┼────────────┼────────────┼────────────┼──────────┼───"
}

# =====================================================================
# SECTION 1: CORE BENCHMARK — ROAD NETWORKS
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SECTION 1: Core Benchmark — DIMACS Road Networks                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

for graph in "${ROAD_GRAPHS[@]}"; do
    short="${graph#USA-road-t.}"
    gr_file="${DATA_DIR}/${graph}.gr"
    ss_file="${DATA_DIR}/${graph}.ss"

    [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && { echo "  ⚠️  SKIP: ${graph}"; continue; }

    echo "┌───────────────────────────────────────────────────────────────────────────────"
    echo "│  ROAD: ${short}  ($(get_node_count "${gr_file}") nodes)"
    echo "├───────────────────────────────────────────────────────────────────────────────"
    print_table_header

    BH_REF_CHECKSUM=""
    for impl_spec in "${CORE_IMPLS[@]}"; do
        run_impl_benchmark "road" "${graph}" "${short}" "${impl_spec}" "${STATS_CSV}" || true
    done

    echo "│  (*) SQ 'updates' = bucket moves only, NOT true dist[] improvements."
    echo "└───────────────────────────────────────────────────────────────────────────────"
    echo ""
done

# =====================================================================
# SECTION 2: CORE BENCHMARK — GRID GRAPHS
# =====================================================================
if [ ${#GRID_GRAPHS[@]} -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SECTION 2: Core Benchmark — Synthetic Grid Graphs                         ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    for graph in "${GRID_GRAPHS[@]}"; do
        gr_file="${DATA_DIR}/${graph}.gr"
        ss_file="${DATA_DIR}/${graph}.ss"

        [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && continue

        echo "┌───────────────────────────────────────────────────────────────────────────────"
        echo "│  GRID: ${graph}  ($(get_node_count "${gr_file}") nodes)"
        echo "├───────────────────────────────────────────────────────────────────────────────"
        print_table_header

        BH_REF_CHECKSUM=""
        for impl_spec in "${CORE_IMPLS[@]}"; do
            run_impl_benchmark "grid" "${graph}" "${graph}" "${impl_spec}" "${STATS_CSV}" || true
        done

        echo "│  (*) SQ 'updates' = bucket moves only."
        echo "└───────────────────────────────────────────────────────────────────────────────"
        echo ""
    done
fi

# =====================================================================
# SECTION 3: OMBI VARIANT COMPARISON
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SECTION 3: OMBI Variant Comparison (base vs opt vs v2-caliber)            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Use a subset of graphs for variant testing
VARIANT_GRAPHS=("USA-road-t.BAY" "USA-road-t.COL" "USA-road-t.FLA" "USA-road-t.NE")

for graph in "${VARIANT_GRAPHS[@]}"; do
    short="${graph#USA-road-t.}"
    gr_file="${DATA_DIR}/${graph}.gr"
    ss_file="${DATA_DIR}/${graph}.ss"
    [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && continue

    echo "┌─ VARIANTS: ${short} ────────────────────────────────────────────────────────"
    printf "│  %-12s │ %10s │ %8s │ %8s │ %16s │ %10s │ %10s │ %8s\n" \
           "Variant" "Median(ms)" "Mean" "StdDev" "95% CI" "Scans" "Updates" "vs base"
    echo "│  ─────────────┼────────────┼──────────┼──────────┼──────────────────┼────────────┼────────────┼─────────"

    base_median=""
    for impl_spec in "${VARIANT_IMPLS[@]}"; do
        IFS=':' read -r label tbin cbin <<< "${impl_spec}"
        [ ! -f "${BIN_DIR}/${tbin}" ] && continue

        # Reuse the core function
        BH_REF_CHECKSUM=""  # not checking vs BH here
        if run_impl_benchmark "road" "${graph}" "${short}_var" "${impl_spec}" "/dev/null" 2>/dev/null; then
            [ "${label}" = "ombi" ] && base_median="${LAST_MEDIAN}"

            local_ratio="N/A"
            if [ -n "${base_median}" ] && [ "${base_median}" != "0" ]; then
                local_ratio=$(echo "${LAST_MEDIAN} ${base_median}" | awk '{printf "%.3f",$1/$2}')
            fi

            echo "${graph},road,${label},${LAST_MEDIAN},${LAST_MEAN},${LAST_STDDEV},${LAST_CI_LOW},${LAST_CI_HIGH},${LAST_SCANS},${LAST_UPDATES},${local_ratio}" >> "${VARIANT_CSV}"
        fi
    done
    echo "└──────────────────────────────────────────────────────────────────────────────"
    echo ""
done

# =====================================================================
# SECTION 4: BW_MULT SENSITIVITY SWEEP
# =====================================================================
if [ "${bw_available}" -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SECTION 4: BW_MULT Sensitivity Sweep (bw = {1,2,3,4,6,8} × minArcLen)    ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    BW_TEST_GRAPHS=("USA-road-t.BAY" "USA-road-t.COL" "USA-road-t.FLA")

    for graph in "${BW_TEST_GRAPHS[@]}"; do
        short="${graph#USA-road-t.}"
        gr_file="${DATA_DIR}/${graph}.gr"
        ss_file="${DATA_DIR}/${graph}.ss"
        [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && continue

        echo "┌─ BW SWEEP: ${short} ──────────────────────────────────────────────────────"
        printf "│  %-8s │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
               "BW_MULT" "Median(ms)" "Mean" "StdDev" "95% CI" "vs bw=4"
        echo "│  ─────────┼────────────┼──────────┼──────────┼──────────────────┼─────────"

        bw4_median=""
        for bw in "${BW_VALS[@]}"; do
            tbin="ombi_bw${bw}"
            cbin="ombi_bw${bw}C"
            [ ! -f "${BIN_DIR}/${tbin}" ] && continue

            impl_spec="bw${bw}:${tbin}:${cbin}"
            BH_REF_CHECKSUM=""
            if run_impl_benchmark "road" "${graph}" "${short}_bw" "${impl_spec}" "/dev/null" 2>/dev/null; then
                [ "${bw}" -eq 4 ] && bw4_median="${LAST_MEDIAN}"

                local_ratio="N/A"
                if [ -n "${bw4_median}" ] && [ "${bw4_median}" != "0" ]; then
                    local_ratio=$(echo "${LAST_MEDIAN} ${bw4_median}" | awk '{printf "%.3f",$1/$2}')
                fi

                ci_str="[$(echo "${LAST_CI_LOW}" | awk '{printf "%.3f",$1}'),$(echo "${LAST_CI_HIGH}" | awk '{printf "%.3f",$1}')]"
                printf "│  %-8s │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
                       "${bw}" \
                       "$(echo "${LAST_MEDIAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_MEAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_STDDEV}" | awk '{printf "%.4f",$1}')" \
                       "${ci_str}" \
                       "${local_ratio}"

                echo "${graph},${bw},${LAST_MEDIAN},${LAST_MEAN},${LAST_STDDEV},${LAST_CI_LOW},${LAST_CI_HIGH},${local_ratio}" >> "${BW_CSV}"
            fi
        done
        echo "└──────────────────────────────────────────────────────────────────────────────"
        echo ""
    done
fi

# =====================================================================
# SECTION 5: HOT_BUCKETS SIZE SWEEP
# =====================================================================
if [ "${hot_available}" -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SECTION 5: HOT_BUCKETS Size Sweep (2^10 .. 2^18)                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    HOT_TEST_GRAPHS=("USA-road-t.BAY" "USA-road-t.COL" "USA-road-t.FLA")

    for graph in "${HOT_TEST_GRAPHS[@]}"; do
        short="${graph#USA-road-t.}"
        gr_file="${DATA_DIR}/${graph}.gr"
        ss_file="${DATA_DIR}/${graph}.ss"
        [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && continue

        echo "┌─ HOT SWEEP: ${short} ─────────────────────────────────────────────────────"
        printf "│  %-6s │ %10s │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
               "2^exp" "Buckets" "Median(ms)" "Mean" "StdDev" "95% CI" "vs 2^14"
        echo "│  ───────┼────────────┼────────────┼──────────┼──────────┼──────────────────┼─────────"

        hot14_median=""
        for exp in "${HOT_EXPS[@]}"; do
            tbin="ombi_hot${exp}"
            cbin="ombi_hot${exp}C"
            [ ! -f "${BIN_DIR}/${tbin}" ] && continue

            hot_buckets=$((1 << exp))
            impl_spec="hot${exp}:${tbin}:${cbin}"
            BH_REF_CHECKSUM=""
            if run_impl_benchmark "road" "${graph}" "${short}_hot" "${impl_spec}" "/dev/null" 2>/dev/null; then
                [ "${exp}" -eq 14 ] && hot14_median="${LAST_MEDIAN}"

                local_ratio="N/A"
                if [ -n "${hot14_median}" ] && [ "${hot14_median}" != "0" ]; then
                    local_ratio=$(echo "${LAST_MEDIAN} ${hot14_median}" | awk '{printf "%.3f",$1/$2}')
                fi

                ci_str="[$(echo "${LAST_CI_LOW}" | awk '{printf "%.3f",$1}'),$(echo "${LAST_CI_HIGH}" | awk '{printf "%.3f",$1}')]"
                printf "│  2^%-4s │ %10d │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
                       "${exp}" "${hot_buckets}" \
                       "$(echo "${LAST_MEDIAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_MEAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_STDDEV}" | awk '{printf "%.4f",$1}')" \
                       "${ci_str}" \
                       "${local_ratio}"

                echo "${graph},${exp},${hot_buckets},${LAST_MEDIAN},${LAST_MEAN},${LAST_STDDEV},${LAST_CI_LOW},${LAST_CI_HIGH},${local_ratio}" >> "${HOT_CSV}"
            fi
        done
        echo "└──────────────────────────────────────────────────────────────────────────────"
        echo ""
    done
fi

# =====================================================================
# SECTION 6: SCALABILITY ANALYSIS
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SECTION 6: Scalability Analysis — Time vs Graph Size                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "  Extracting node counts and computing log-log regression..."
echo ""

# Collect data for scalability from stats CSV
for graph in "${ROAD_GRAPHS[@]}"; do
    gr_file="${DATA_DIR}/${graph}.gr"
    [ ! -f "${gr_file}" ] && continue
    nodes=$(get_node_count "${gr_file}")

    # For each impl, get median from stats CSV
    while IFS=, read -r g gt impl median rest; do
        [ "${g}" != "${graph}" ] && continue
        [ "${gt}" != "road" ] && continue
        log_n=$(echo "${nodes}" | awk '{printf "%.4f", log($1)/log(10)}')
        log_t=$(echo "${median}" | awk '{printf "%.4f", log($1)/log(10)}')
        echo "road,${impl},${graph},${nodes},${median},${log_n},${log_t}" >> "${SCALABILITY_CSV}"
    done < <(tail -n +2 "${STATS_CSV}")
done

# Print scalability summary — log-log slope per impl
printf "  %-10s │ %12s │ %s\n" "Impl" "Slope(log-log)" "Interpretation"
echo "  ───────────┼──────────────┼──────────────────────────────────────"

# Get unique impls from scalability CSV
tail -n +2 "${SCALABILITY_CSV}" 2>/dev/null | cut -d, -f2 | sort -u | while read -r impl; do
    # Linear regression on log(n) vs log(t) using awk
    slope=$(grep ",${impl}," "${SCALABILITY_CSV}" | awk -F, '
    BEGIN { n=0; sx=0; sy=0; sxy=0; sxx=0 }
    {
        x=$6; y=$7  # log_nodes, log_ms
        sx+=x; sy+=y; sxy+=x*y; sxx+=x*x; n++
    }
    END {
        if (n<2) { print "N/A"; exit }
        slope = (n*sxy - sx*sy) / (n*sxx - sx*sx)
        printf "%.3f", slope
    }')

    interp=""
    if [ "${slope}" != "N/A" ]; then
        sval=$(echo "${slope}" | awk '{printf "%.1f", $1}')
        if (( $(echo "${slope} < 1.1" | bc -l) )); then
            interp="≈ O(n) — near-linear"
        elif (( $(echo "${slope} < 1.3" | bc -l) )); then
            interp="≈ O(n log n) — expected for Dijkstra"
        elif (( $(echo "${slope} < 1.6" | bc -l) )); then
            interp="≈ O(n^1.5) — superlinear"
        else
            interp="≈ O(n^${sval}) — check for issues"
        fi
    fi

    printf "  %-10s │ %12s │ %s\n" "${impl}" "${slope}" "${interp}"
done

echo ""
echo "  Slope = d(log time) / d(log nodes). For Dijkstra with a good PQ,"
echo "  expect ~1.0–1.2 on road networks (near-linear in practice due to"
echo "  sparse graphs and small average degree)."
echo ""

# =====================================================================
# SUMMARY TABLES
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

# Get unique impls preserving order
for impl_spec in "${CORE_IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    printf "  %-10s" "${label}"
    for graph in "${ROAD_GRAPHS[@]}"; do
        ratio=$(grep "^${graph},road,${label}," "${STATS_CSV}" | head -1 | cut -d, -f17)
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
            if echo "${graph}" | grep -q "${wlabel}$"; then
                local_grids+=("${graph}")
                short="${graph%%_${wlabel}}"
                short="${short#grid_}"
                printf " │ %12s" "${short}"
            fi
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
                ratio=$(grep "^${graph},grid,${label}," "${STATS_CSV}" | head -1 | cut -d, -f17)
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
            mem=$(grep "^${graph},road,${label}," "${STATS_CSV}" | head -1 | cut -d, -f13)
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
echo "  UPDATES (i):    ⚠️  CRITICAL FAIRNESS CAVEAT:"
echo "    BH,4H,FH,PH,Dial,R1,R2,OMBI: count every dist[v] improvement."
echo "    SQ (Goldberg): counts BUCKET MOVES only (bckOld != bckNew)."
echo "    SQ's 'i' is LOWER and NOT directly comparable. Marked with (*)."
echo ""
echo "  MEMORY:         Peak RSS via GNU /usr/bin/time -v. Includes graph storage."
echo "                  Delta between impls = priority queue overhead."
echo ""
echo "  BINARY SIZE:    Stripped binary size. Larger = more inlined code."
echo ""
echo "  COMPILE TIME:   Single-threaded (make -j1) per target. Clean build."
echo ""
echo "  SCALABILITY:    Log-log regression of median time vs node count."
echo "                  Slope ~1.0 = near-linear. Slope ~1.2 = O(n log n)."
echo ""
echo "  GRAPHS:"
echo "    Road:  Real DIMACS 9th Challenge road networks."
echo "    Grid:  Synthetic W×W grids, uniform degree-4, random weights."
echo "      w100    — narrow [1,100]: many bucket collisions"
echo "      w100000 — wide [1,100000]: spread across buckets"
echo ""
echo "  OMBI VARIANTS:"
echo "    ombi      — Standard (ombi.cc): simpler, baseline correctness."
echo "    ombi_opt  — Optimized: packed state, pool alloc, force-inline."
echo "    ombi_v2   — Caliber/F-set: exact-distance vertices skip buckets."
echo ""
echo "  SENSITIVITY:"
echo "    BW_MULT:     Bucket width = BW_MULT × minArcLen."
echo "                 Default=4. Tested: {1,2,3,4,6,8}."
echo "    HOT_BUCKETS: Number of hot-zone circular buckets."
echo "                 Default=2^14 (16384). Tested: 2^10..2^18."
echo ""
echo "  CORRECTNESS:   MD5 of all source→distance checksums vs BH reference."
echo ""

# =====================================================================
# DONE
# =====================================================================
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Output files:"
echo "    Raw data:       ${RAW_CSV}"
echo "    Statistics:     ${STATS_CSV}"
echo "    Memory:         ${MEMORY_CSV}"
echo "    Checksums:      ${CHECKSUM_CSV}"
echo "    Build info:     ${BUILD_CSV}"
echo "    Scalability:    ${SCALABILITY_CSV}"
echo "    Variants:       ${VARIANT_CSV}"
echo "    BW sweep:       ${BW_CSV}"
echo "    HOT sweep:      ${HOT_CSV}"
echo ""
echo "  Total benchmark time: $((SECONDS / 60))m $((SECONDS % 60))s"
echo "═══════════════════════════════════════════════════════════════════════════════"
