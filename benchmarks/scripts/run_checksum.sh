#!/bin/bash
#
# run_checksum.sh — Quick correctness verification (no timing)
#
# Runs checksum binaries on all graphs, verifies all implementations
# produce identical distance arrays (compared to Binary Heap reference).
#
# Usage:
#   cd /path/to/ombi
#   export DATA_DIR=/path/to/dimacs/data
#   ./benchmarks/scripts/run_checksum.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/bin"
RESULTS_DIR="${PROJECT_ROOT}/benchmarks/results"

DATA_DIR="${DATA_DIR:-/path/to/dimacs/data}"

GRAPHS=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
)

IMPLS=( "dij_bhC" "dij_4hC" "dij_fhC" "dij_phC" "dij_dialC" "dij_r1C" "dij_r2C" "ombiC" "sqC" )

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  OMBI — Checksum Verification                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -d "${DATA_DIR}" ] || [ "${DATA_DIR}" = "/path/to/dimacs/data" ]; then
    echo "  ❌ Set DATA_DIR first:  export DATA_DIR=/path/to/data"
    exit 1
fi

mkdir -p "${RESULTS_DIR}"
total=0
passed=0
failed=0

for graph in "${GRAPHS[@]}"; do
    gr_file="${DATA_DIR}/${graph}.gr"
    ss_file="${DATA_DIR}/${graph}.ss"
    short="${graph#USA-road-t.}"

    if [ ! -f "${gr_file}" ] || [ ! -f "${ss_file}" ]; then
        echo "  ⚠️  SKIP: ${short} (data not found)"
        continue
    fi

    echo "┌─ ${short} ──────────────────────────────────────"

    # Reference: Binary Heap
    ref_file="${RESULTS_DIR}/${graph}_ref.txt"
    "${BIN_DIR}/dij_bhC" "${gr_file}" "${ss_file}" "${ref_file}" 2>/dev/null
    ref_md5=$(grep '^d ' "${ref_file}" | md5sum | awk '{print $1}')

    for impl in "${IMPLS[@]}"; do
        label="${impl%C}"
        label="${label#dij_}"
        [ "${impl}" = "ombiC" ] && label="ombi"
        [ "${impl}" = "sqC" ] && label="sq"

        out_file="${RESULTS_DIR}/${graph}_${label}_chk.txt"
        "${BIN_DIR}/${impl}" "${gr_file}" "${ss_file}" "${out_file}" 2>/dev/null
        chk_md5=$(grep '^d ' "${out_file}" | md5sum | awk '{print $1}')

        total=$((total + 1))
        if [ "${chk_md5}" = "${ref_md5}" ]; then
            echo "│  ${label}: ✅ match"
            passed=$((passed + 1))
        else
            echo "│  ${label}: ❌ MISMATCH"
            failed=$((failed + 1))
        fi
    done

    echo "└──────────────────────────────────────────────"
    echo ""
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Result: ${passed}/${total} passed, ${failed} failed"
echo "╚══════════════════════════════════════════════════════════════╝"

[ "${failed}" -eq 0 ] && exit 0 || exit 1
