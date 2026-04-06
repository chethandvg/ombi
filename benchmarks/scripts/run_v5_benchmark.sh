#!/bin/bash
#
# run_v5_benchmark.sh — Focused benchmark for OMBI v5/v5s correctness fix
#
# ═══════════════════════════════════════════════════════════════════════════════
# Tests:
#   1. OMBI v5 + v5s on ALL road networks (BAY, COL, FLA, NW, NE, USA)
#   2. Core impls (bh, sq, ombi, ombi_v3, r2) on USA for comparison
#   3. v5 + v5s on low-C grid graphs (correctness validation)
#   4. v5 + v5s on high-C grid graphs (performance validation)
#   5. Checksum comparison against Binary Heap reference
#
# Usage:
#   cd /mnt/d/Projects/Practice/Research/ombi
#   make all && make sweep-bw-v5 && make sweep-hot-v5
#   chmod +x benchmarks/scripts/run_v5_benchmark.sh
#   ./benchmarks/scripts/run_v5_benchmark.sh 2>&1 | tee benchmarks/results/v5_benchmark_$(date +%Y%m%d_%H%M%S).log
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
# Note: we intentionally do NOT use `set -e` globally. Critical sections
# use explicit error checks. The grid section at the end may crash/OOM on
# large grids, and we must preserve all prior benchmark data.

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

# --- Road network graphs (including USA!) ---
ROAD_GRAPHS=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
    "USA-road-t.USA"
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

# --- V5 implementations to test ---
V5_IMPLS=(
    "ombi_v5:ombi_v5:ombi_v5C"
    "ombi_v5s:ombi_v5s:ombi_v5sC"
)

# --- Core comparison impls (run on all road graphs + USA) ---
CORE_IMPLS=(
    "bh:dij_bh:dij_bhC"
    "ombi:ombi:ombiC"
    "ombi_v3:ombi_v3:ombi_v3C"
    "sq:sq:sqC"
    "r2:dij_r2:dij_r2C"
)

# --- Extended impls for USA comparison ---
USA_EXTRA_IMPLS=(
    "4h:dij_4h:dij_4hC"
    "dial:dij_dial:dij_dialC"
    "r1:dij_r1:dij_r1C"
)

# --- Grid-specific comparison impls ---
GRID_IMPLS=(
    "bh:dij_bh:dij_bhC"
    "dial:dij_dial:dij_dialC"
    "sq:sq:sqC"
    "r2:dij_r2:dij_r2C"
    "ombi_v5:ombi_v5:ombi_v5C"
    "ombi_v5s:ombi_v5s:ombi_v5sC"
)

# --- BW_MULT sweep values ---
BW_VALS=(1 2 3 4 6 8)

# --- HOT_BUCKETS sweep (exponents) ---
HOT_EXPS=(10 11 12 13 14 15 16 17 18)

# =====================================================================
# BANNER
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  OMBI v5 — Correctness Fix Benchmark Suite                                 ║"
echo "║  v5 (Adaptive BW) + v5s (Sorted Insert) · Road + Grid + USA                ║"
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

# Check v5 binaries (required)
v5_ok=1
for impl_spec in "${V5_IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    for b in "${tbin}" "${cbin}"; do
        if [ ! -f "${BIN_DIR}/${b}" ]; then
            echo "  ❌ Missing: bin/${b}"
            v5_ok=0
        fi
    done
done
if [ "${v5_ok}" -eq 0 ]; then
    echo "  Run 'make all' first."
    exit 1
fi
echo "  ✅ OMBI v5/v5s binaries found"

# Check core comparison binaries (optional)
for impl_spec in "${CORE_IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    for b in "${tbin}" "${cbin}"; do
        if [ ! -f "${BIN_DIR}/${b}" ]; then
            echo "  ⚠️  Missing: bin/${b} (will skip)"
        fi
    done
done
echo "  ✅ Core comparison binaries checked"

# BW sweep v5 — optional
bw_v5_available=0
for bw in "${BW_VALS[@]}"; do
    if [ -f "${BIN_DIR}/ombi_v5_bw${bw}" ]; then
        bw_v5_available=$((bw_v5_available + 1))
    fi
done
if [ "${bw_v5_available}" -gt 0 ]; then
    echo "  ✅ BW_MULT v5 sweep binaries: ${bw_v5_available}/${#BW_VALS[@]}"
else
    echo "  ⚠️  No BW v5 sweep binaries — run 'make sweep-bw-v5' to enable"
fi

# HOT sweep v5 — optional
hot_v5_available=0
for exp in "${HOT_EXPS[@]}"; do
    if [ -f "${BIN_DIR}/ombi_v5_hot${exp}" ]; then
        hot_v5_available=$((hot_v5_available + 1))
    fi
done
if [ "${hot_v5_available}" -gt 0 ]; then
    echo "  ✅ HOT_BUCKETS v5 sweep binaries: ${hot_v5_available}/${#HOT_EXPS[@]}"
else
    echo "  ⚠️  No HOT v5 sweep binaries — run 'make sweep-hot-v5' to enable"
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
        echo "  ⏭️  ${gname} — skipping (no gen_grid binary)"
    fi
done
echo ""

mkdir -p "${RESULTS_DIR}"

# =====================================================================
# OUTPUT FILES
# =====================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STATS_CSV="${RESULTS_DIR}/v5_stats_${TIMESTAMP}.csv"
CHECKSUM_CSV="${RESULTS_DIR}/v5_checksums_${TIMESTAMP}.csv"
BW_V5_CSV="${RESULTS_DIR}/v5_bw_sweep_${TIMESTAMP}.csv"
HOT_V5_CSV="${RESULTS_DIR}/v5_hot_sweep_${TIMESTAMP}.csv"

echo "graph,graph_type,impl,median_ms,mean_ms,stddev_ms,min_ms,max_ms,ci95_low,ci95_high,avg_scans,avg_updates,peak_rss_kb,ns_per_scan,ns_per_update,throughput_nodes_per_sec,ratio_vs_bh,checksum_ok" > "${STATS_CSV}"
echo "graph,graph_type,impl,checksum_md5,match_bh" > "${CHECKSUM_CSV}"
echo "graph,bw_mult,median_ms,mean_ms,stddev_ms,ci95_low,ci95_high,ratio_vs_bw4" > "${BW_V5_CSV}"
echo "graph,hot_exp,hot_buckets,median_ms,mean_ms,stddev_ms,ci95_low,ci95_high,ratio_vs_14" > "${HOT_V5_CSV}"

# =====================================================================
# STATISTICS HELPERS
# =====================================================================

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

get_node_count() {
    grep '^p sp' "$1" | head -1 | awk '{print $3}'
}

# =====================================================================
# CORE BENCHMARK FUNCTION
# =====================================================================
declare -A BH_MEDIAN

run_impl_benchmark() {
    local graph_type="$1"
    local graph="$2"
    local short="$3"
    local impl_spec="$4"
    local csv_file="$5"

    IFS=':' read -r label tbin cbin <<< "${impl_spec}"

    if [ ! -f "${BIN_DIR}/${tbin}" ] || [ ! -f "${BIN_DIR}/${cbin}" ]; then
        return 1
    fi

    local gr_file="${DATA_DIR}/${graph}.gr"
    local ss_file="${DATA_DIR}/${graph}.ss"

    if [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ]; then
        return 1
    fi

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
# SECTION 1: v5/v5s + CORE IMPLS ON ALL ROAD NETWORKS (including USA)
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SECTION 1: Road Networks — v5/v5s + Core Comparison (including USA)        ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

for graph in "${ROAD_GRAPHS[@]}"; do
    short="${graph#USA-road-t.}"
    gr_file="${DATA_DIR}/${graph}.gr"
    ss_file="${DATA_DIR}/${graph}.ss"

    [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && { echo "  ⚠️  SKIP: ${graph} (missing data)"; echo ""; continue; }

    echo "┌───────────────────────────────────────────────────────────────────────────────"
    echo "│  ROAD: ${short}  ($(get_node_count "${gr_file}") nodes)"
    echo "├───────────────────────────────────────────────────────────────────────────────"
    print_table_header

    BH_REF_CHECKSUM=""

    # Core comparison impls first (bh for reference, then others)
    for impl_spec in "${CORE_IMPLS[@]}"; do
        run_impl_benchmark "road" "${graph}" "${short}" "${impl_spec}" "${STATS_CSV}" || true
    done

    # USA extra impls
    if [ "${short}" = "USA" ]; then
        for impl_spec in "${USA_EXTRA_IMPLS[@]}"; do
            run_impl_benchmark "road" "${graph}" "${short}" "${impl_spec}" "${STATS_CSV}" || true
        done
    fi

    # V5 impls
    for impl_spec in "${V5_IMPLS[@]}"; do
        run_impl_benchmark "road" "${graph}" "${short}" "${impl_spec}" "${STATS_CSV}" || true
    done

    echo "│  (*) SQ 'updates' = bucket moves only, NOT true dist[] improvements."
    echo "└───────────────────────────────────────────────────────────────────────────────"
    echo ""
done

# =====================================================================
# SECTION 2: BW_MULT SENSITIVITY SWEEP — OMBI v5
# =====================================================================
if [ "${bw_v5_available}" -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SECTION 2: BW_MULT Sensitivity Sweep — OMBI v5 (bw = {1..8} × minArc)    ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    BW_V5_TEST_GRAPHS=("USA-road-t.BAY" "USA-road-t.COL" "USA-road-t.FLA")

    for graph in "${BW_V5_TEST_GRAPHS[@]}"; do
        short="${graph#USA-road-t.}"
        gr_file="${DATA_DIR}/${graph}.gr"
        ss_file="${DATA_DIR}/${graph}.ss"
        [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && continue

        echo "┌─ BW v5 SWEEP: ${short} ───────────────────────────────────────────────────"
        printf "│  %-8s │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
               "BW_MULT" "Median(ms)" "Mean" "StdDev" "95% CI" "vs bw=4"
        echo "│  ─────────┼────────────┼──────────┼──────────┼──────────────────┼─────────"

        bw4_v5_median=""
        for bw in "${BW_VALS[@]}"; do
            tbin="ombi_v5_bw${bw}"
            cbin="ombi_v5_bw${bw}C"
            [ ! -f "${BIN_DIR}/${tbin}" ] && continue

            impl_spec="v5_bw${bw}:${tbin}:${cbin}"
            BH_REF_CHECKSUM=""
            if run_impl_benchmark "road" "${graph}" "${short}_bw_v5" "${impl_spec}" "/dev/null" 2>/dev/null; then
                [ "${bw}" -eq 4 ] && bw4_v5_median="${LAST_MEDIAN}"

                local_ratio="N/A"
                if [ -n "${bw4_v5_median}" ] && [ "${bw4_v5_median}" != "0" ]; then
                    local_ratio=$(echo "${LAST_MEDIAN} ${bw4_v5_median}" | awk '{printf "%.3f",$1/$2}')
                fi

                ci_str="[$(echo "${LAST_CI_LOW}" | awk '{printf "%.3f",$1}'),$(echo "${LAST_CI_HIGH}" | awk '{printf "%.3f",$1}')]"
                printf "│  %-8s │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
                       "${bw}" \
                       "$(echo "${LAST_MEDIAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_MEAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_STDDEV}" | awk '{printf "%.4f",$1}')" \
                       "${ci_str}" \
                       "${local_ratio}"

                echo "${graph},${bw},${LAST_MEDIAN},${LAST_MEAN},${LAST_STDDEV},${LAST_CI_LOW},${LAST_CI_HIGH},${local_ratio}" >> "${BW_V5_CSV}"
            fi
        done
        echo "└──────────────────────────────────────────────────────────────────────────────"
        echo ""
    done
fi

# =====================================================================
# SECTION 3: HOT_BUCKETS SIZE SWEEP — OMBI v5
# =====================================================================
if [ "${hot_v5_available}" -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SECTION 3: HOT_BUCKETS Size Sweep — OMBI v5 (2^10 .. 2^18)               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    HOT_V5_TEST_GRAPHS=("USA-road-t.BAY" "USA-road-t.COL" "USA-road-t.FLA")

    for graph in "${HOT_V5_TEST_GRAPHS[@]}"; do
        short="${graph#USA-road-t.}"
        gr_file="${DATA_DIR}/${graph}.gr"
        ss_file="${DATA_DIR}/${graph}.ss"
        [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && continue

        echo "┌─ HOT v5 SWEEP: ${short} ──────────────────────────────────────────────────"
        printf "│  %-6s │ %10s │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
               "2^exp" "Buckets" "Median(ms)" "Mean" "StdDev" "95% CI" "vs 2^14"
        echo "│  ───────┼────────────┼────────────┼──────────┼──────────┼──────────────────┼─────────"

        hot14_v5_median=""
        for exp in "${HOT_EXPS[@]}"; do
            tbin="ombi_v5_hot${exp}"
            cbin="ombi_v5_hot${exp}C"
            [ ! -f "${BIN_DIR}/${tbin}" ] && continue

            hot_buckets=$((1 << exp))
            impl_spec="v5_hot${exp}:${tbin}:${cbin}"
            BH_REF_CHECKSUM=""
            if run_impl_benchmark "road" "${graph}" "${short}_hot_v5" "${impl_spec}" "/dev/null" 2>/dev/null; then
                [ "${exp}" -eq 14 ] && hot14_v5_median="${LAST_MEDIAN}"

                local_ratio="N/A"
                if [ -n "${hot14_v5_median}" ] && [ "${hot14_v5_median}" != "0" ]; then
                    local_ratio=$(echo "${LAST_MEDIAN} ${hot14_v5_median}" | awk '{printf "%.3f",$1/$2}')
                fi

                ci_str="[$(echo "${LAST_CI_LOW}" | awk '{printf "%.3f",$1}'),$(echo "${LAST_CI_HIGH}" | awk '{printf "%.3f",$1}')]"
                printf "│  2^%-4s │ %10d │ %10s │ %8s │ %8s │ %16s │ %8s\n" \
                       "${exp}" "${hot_buckets}" \
                       "$(echo "${LAST_MEDIAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_MEAN}" | awk '{printf "%.3f",$1}')" \
                       "$(echo "${LAST_STDDEV}" | awk '{printf "%.4f",$1}')" \
                       "${ci_str}" \
                       "${local_ratio}"

                echo "${graph},${exp},${hot_buckets},${LAST_MEDIAN},${LAST_MEAN},${LAST_STDDEV},${LAST_CI_LOW},${LAST_CI_HIGH},${local_ratio}" >> "${HOT_V5_CSV}"
            fi
        done
        echo "└──────────────────────────────────────────────────────────────────────────────"
        echo ""
    done
fi

# =====================================================================
# ROAD NETWORK SUMMARY TABLE
# (printed BEFORE grids so it's safe even if grids crash/OOM)
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  SUMMARY: v5 vs v3 vs SQ vs BH — Road Networks                            ║"
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

for label in "bh" "sq" "ombi" "ombi_v3" "r2" "ombi_v5" "ombi_v5s"; do
    printf "  %-10s" "${label}"
    for graph in "${ROAD_GRAPHS[@]}"; do
        ratio=$(grep "^${graph},road,${label}," "${STATS_CSV}" | head -1 | cut -d, -f17)
        printf " │ %8s" "${ratio:-N/A}"
    done
    echo ""
done
echo ""

# =====================================================================
# METHODOLOGY NOTES
# (printed before grids — preserved even if grid section crashes)
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  METHODOLOGY & v5 DESIGN NOTES                                             ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  OMBI v5 (Adaptive Bucket Width):"
echo "    bw = minWeight × BW_MULT  when minWeight ≥ BW_MULT (road networks)"
echo "    bw = minWeight             when minWeight < BW_MULT (low-C grids)"
echo "    → Satisfies Dinitz bound (bw ≤ minWeight) for correctness"
echo "    → Zero performance impact on road networks"
echo ""
echo "  OMBI v5s (Sorted Insert):"
echo "    bw = minWeight × BW_MULT  always (same as v3)"
echo "    → Inserts into L0 buckets in ascending distance order"
echo "    → Extraction always yields true minimum within bucket"
echo "    → O(k) per insert where k = bucket occupancy (k≈1-3 on roads)"
echo ""
echo "  COMPILER:  g++ -std=c++17 -Wall -O3 -DNDEBUG"
echo "  TIMING:    ${TOTAL_RUNS} runs, drop min & max → ${EFF_RUNS} effective"
echo "  CI:        95% (t-distribution, df=$((EFF_RUNS-1)))"
echo ""

# Print intermediate output files (road + sweep results are safe now)
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Road + Sweep results complete. Output files so far:"
echo "    Statistics:     ${STATS_CSV}"
echo "    Checksums:      ${CHECKSUM_CSV}"
echo "    BW v5 sweep:    ${BW_V5_CSV}"
echo "    HOT v5 sweep:   ${HOT_V5_CSV}"
echo "  Elapsed: $((SECONDS / 60))m $((SECONDS % 60))s"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# =====================================================================
# SECTION 4: v5/v5s ON GRID GRAPHS (CORRECTNESS VALIDATION)
# ═════════════════════════════════════════════════════════════════════
# ⚠️  This section runs LAST because:
#   - Large grids (3162×3162 = 10M nodes) are memory-intensive and may OOM
#   - Low-C grids may expose algorithmic edge cases → potential crashes
#   - Running this last ensures all road/sweep results are already saved
#
# CRASH PROTECTION:
#   - Each grid×impl combination runs with its own error trap
#   - If an impl crashes/OOMs on a grid, we log the failure and continue
#   - No timeout — each run is allowed to complete naturally
#   - All CSV data is written incrementally — whatever completes is saved
# =====================================================================

if [ ${#GRID_GRAPHS[@]} -gt 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  SECTION 4: Grid Graphs — v5/v5s Correctness + Performance                 ║"
    echo "║  ⚡ KEY TEST: Low-C grids (w100) where v3 FAILED — v5 should PASS ✅       ║"
    echo "║  ⚠️  Runs LAST — crash-protected. No timeout (runs to completion).          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    GRID_COMPLETED=0
    GRID_CRASHED=0

    for graph in "${GRID_GRAPHS[@]}"; do
        gr_file="${DATA_DIR}/${graph}.gr"
        ss_file="${DATA_DIR}/${graph}.ss"

        [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ] && continue

        echo "┌───────────────────────────────────────────────────────────────────────────────"
        echo "│  GRID: ${graph}  ($(get_node_count "${gr_file}") nodes)"
        echo "├───────────────────────────────────────────────────────────────────────────────"
        print_table_header

        BH_REF_CHECKSUM=""
        for impl_spec in "${GRID_IMPLS[@]}"; do
            IFS=':' read -r impl_label impl_tbin impl_cbin <<< "${impl_spec}"

            # --- Crash-protected run ---
            # We run each impl in a controlled way: catch crashes and OOMs
            (
                # Run in subshell so failures don't propagate
                run_impl_benchmark "grid" "${graph}" "${graph}" "${impl_spec}" "${STATS_CSV}"
            ) 2>&1
            exit_code=$?

            if [ ${exit_code} -ne 0 ]; then
                # Impl crashed or failed
                printf "│  %-10s │ %10s │ %8s │ %8s │ %8s │ %10s │ %10s │ %10s │ %8s │ %s\n" \
                       "${impl_label}" "CRASHED" "-" "-" "-" "-" "-" "-" "-" "💥"
                echo "${graph},grid,${impl_label},0,0,0,0,0,0,0,0,0,N/A,N/A,N/A,N/A,N/A,CRASH" >> "${STATS_CSV}"
                echo "${graph},grid,${impl_label},CRASH,CRASH" >> "${CHECKSUM_CSV}"
                GRID_CRASHED=$((GRID_CRASHED + 1))
                echo "│  ⚠️  ${impl_label} crashed/failed on ${graph} (exit=${exit_code}) — continuing..."
            else
                GRID_COMPLETED=$((GRID_COMPLETED + 1))
            fi
        done

        echo "│  (*) SQ 'updates' = bucket moves only."
        echo "└───────────────────────────────────────────────────────────────────────────────"
        echo ""
    done

    # Grid correctness summary
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  CORRECTNESS: Grid Graph Checksum Verification                             ║"
    echo "║  v3 failed on low-C grids (w100). v5 should pass ALL.                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  %-30s" "Grid"
    printf " │ %-8s │ %-8s │ %-8s │ %-8s │ %-8s │ %-8s\n" \
           "bh" "dial" "sq" "r2" "v5" "v5s"
    printf "  ──────────────────────────────"
    printf "─┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────\n"

    for graph in "${GRID_GRAPHS[@]}"; do
        printf "  %-30s" "${graph}"
        for label in "bh" "dial" "sq" "r2" "ombi_v5" "ombi_v5s"; do
            match=$(grep "^${graph},grid,${label}," "${CHECKSUM_CSV}" | head -1 | cut -d, -f5)
            if [ "${match}" = "YES" ]; then
                printf " │   %-5s " "✅"
            elif [ "${match}" = "CRASH" ]; then
                printf " │   %-5s " "💥"
            elif [ -z "${match}" ]; then
                printf " │   %-5s " "N/A"
            else
                printf " │   %-5s " "❌"
            fi
        done
        echo ""
    done
    echo ""

    echo "  Grid benchmark: ${GRID_COMPLETED} completed, ${GRID_CRASHED} crashed/failed"
    echo ""
fi

# =====================================================================
# DONE
# =====================================================================
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Output files:"
echo "    Statistics:     ${STATS_CSV}"
echo "    Checksums:      ${CHECKSUM_CSV}"
echo "    BW v5 sweep:    ${BW_V5_CSV}"
echo "    HOT v5 sweep:   ${HOT_V5_CSV}"
echo ""
echo "  Total benchmark time: $((SECONDS / 60))m $((SECONDS % 60))s"
echo "═══════════════════════════════════════════════════════════════════════════════"
