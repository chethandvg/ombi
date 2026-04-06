#!/bin/bash
# shellcheck shell=bash
#
# run_benchmark.sh — Run OMBI vs all baselines on DIMACS road networks
#
# Runs each implementation on each graph, collects timing and checksums,
# verifies correctness against Binary Heap reference.
#
# Usage:
#   cd /path/to/ombi
#   ./benchmarks/scripts/run_benchmark.sh
#
# Prerequisites:
#   1. Build first: make all
#   2. Set DATA_DIR below to your DIMACS .gr/.ss file location
#   3. Download data from: http://www.dis.uniroma1.it/challenge9/download.shtml
#

set -euo pipefail

# =====================================================================
# CONFIGURATION — Edit these paths for your environment
# =====================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/bin"
RESULTS_DIR="${PROJECT_ROOT}/benchmarks/results"

# *** EDIT THIS: path to your DIMACS road network .gr and .ss files ***
DATA_DIR="${DATA_DIR:-${PROJECT_ROOT}/data}"

RUNS=5  # Number of timing runs per graph (median reported)

GRAPHS=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
    # "USA-road-t.USA"   # Uncomment for full USA (23.9M nodes — very slow!)
)

# All implementations to benchmark
# Format: label:timing_binary:checksum_binary
IMPLS=(
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
)

# =====================================================================
# VALIDATION
# =====================================================================

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  OMBI — Full Benchmark Suite                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Project root: ${PROJECT_ROOT}"
echo "  Data dir:     ${DATA_DIR}"
echo "  Runs:         ${RUNS}"
echo ""

# Check binaries exist
missing=0
for impl_spec in "${IMPLS[@]}"; do
    IFS=':' read -r label tbin cbin <<< "${impl_spec}"
    if [ ! -f "${BIN_DIR}/${tbin}" ]; then
        echo "  ❌ Missing: bin/${tbin}"
        missing=1
    fi
done
if [ "${missing}" -eq 1 ]; then
    echo ""
    echo "  Run 'make all' first to build all binaries."
    exit 1
fi
echo "  ✅ All binaries found"
echo ""

# Check data directory
if [ ! -d "${DATA_DIR}" ]; then
    echo "  ❌ DATA_DIR not set or doesn't exist: ${DATA_DIR}"
    echo ""
    echo "  Set it via environment variable:"
    echo "    export DATA_DIR=/path/to/your/dimacs/data"
    echo "    ./benchmarks/scripts/run_benchmark.sh"
    echo ""
    echo "  Or edit DATA_DIR in this script."
    exit 1
fi

mkdir -p "${RESULTS_DIR}"

# =====================================================================
# CSV headers
# =====================================================================
CSV="${RESULTS_DIR}/benchmark_results.csv"
CHK="${RESULTS_DIR}/checksum_verification.csv"
echo "graph,impl,run,time_ms,scans,improvements" > "${CSV}"
echo "graph,impl,checksum_md5,match_bh" > "${CHK}"

# =====================================================================
# RUN BENCHMARKS
# =====================================================================
echo "--- Running benchmarks ---"
echo ""

for graph in "${GRAPHS[@]}"; do
    gr_file="${DATA_DIR}/${graph}.gr"
    ss_file="${DATA_DIR}/${graph}.ss"
    short="${graph#USA-road-t.}"

    if [ ! -f "${gr_file}" ]; then
        echo "  ⚠️  SKIP: ${gr_file} not found"
        continue
    fi
    if [ ! -f "${ss_file}" ]; then
        echo "  ⚠️  SKIP: ${ss_file} not found"
        continue
    fi

    echo "┌─ ${short} ──────────────────────────────────────"

    ref_checksum=""

    for impl_spec in "${IMPLS[@]}"; do
        IFS=':' read -r label tbin cbin <<< "${impl_spec}"

        echo -n "│  ${label}: "

        # --- Timing runs ---
        for run in $(seq 1 ${RUNS}); do
            out_file="${RESULTS_DIR}/${graph}_${label}_run${run}.txt"
            rm -f "${out_file}"
            "${BIN_DIR}/${tbin}" "${gr_file}" "${ss_file}" "${out_file}" 2>/dev/null

            t_ms=$(grep '^t ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "N/A")
            scans=$(grep '^v ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "N/A")
            improv=$(grep '^i ' "${out_file}" 2>/dev/null | awk '{print $2}' || echo "N/A")
            echo "${graph},${label},${run},${t_ms},${scans},${improv}" >> "${CSV}"
        done

        # --- Checksum verification ---
        cout_file="${RESULTS_DIR}/${graph}_${label}_checksum.txt"
        rm -f "${cout_file}"
        "${BIN_DIR}/${cbin}" "${gr_file}" "${ss_file}" "${cout_file}" 2>/dev/null

        chk_md5=$(grep '^d ' "${cout_file}" 2>/dev/null | md5sum | awk '{print $1}')

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

        # Show median timing from last run
        echo "${match} (last run: ${t_ms} ms)"
        echo "${graph},${label},${chk_md5},${match_csv}" >> "${CHK}"
    done

    echo "└──────────────────────────────────────────────"
    echo ""
done

# =====================================================================
# SUMMARY
# =====================================================================
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Benchmark Complete!                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Results:   ${CSV}"
echo "  Checksums: ${CHK}"
echo ""
echo "  To extract median timings:"
echo "    sort -t, -k1,1 -k2,2 -k4,4n ${CSV} | awk -F, '..."
echo ""
echo "  Checksum summary:"
fails=$(grep ",NO$" "${CHK}" 2>/dev/null | wc -l || echo 0)
total=$(wc -l < "${CHK}" 2>/dev/null || echo 0)
total=$((total - 1))  # subtract header
echo "    ${total} tests, $((total - fails)) passed, ${fails} failed"
