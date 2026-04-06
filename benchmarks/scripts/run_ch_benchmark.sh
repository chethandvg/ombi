#!/bin/bash
# shellcheck shell=bash
#
# HISTORICAL — This script references the old directory structure.
# Use run_benchmark.sh instead for the reorganized repository.
#
# =============================================================================
# CH (Contraction Hierarchies) Benchmark
# =============================================================================
# Run from: /mnt/d/Projects/Practice/Research/nexus3/C_Lang/v27-dimacs
# Usage:    bash run_ch_benchmark.sh 2>&1 | tee results/ch_benchmark.log
#
# This script:
#   1. Compiles CH (normal + checksum mode)
#   2. Runs preprocessing + SSSP queries on all 5 standard graphs
#   3. Verifies correctness against BH checksums
#   4. Outputs CSV with preprocessing time, query time, shortcuts, search space
# =============================================================================

set -e

CXXFLAGS="-std=c++17 -Wall -O3 -DNDEBUG"
DATA_DIR="/mnt/d/Projects/Practice/Research/nexus3/csharp/data"
RESULTS_DIR="results"
CH_CSV="${RESULTS_DIR}/ch_benchmark.csv"
CH_CHECKSUMS="${RESULTS_DIR}/ch_checksums.csv"

GRAPHS="BAY COL FLA NW NE"

echo "============================================"
echo " Contraction Hierarchies Benchmark"
echo " Started: $(date)"
echo "============================================"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# =============================================================================
# STEP 1: Compile
# =============================================================================
echo ""
echo "--- Step 1: Compiling ---"

echo "  Compiling CH (timing mode)..."
g++ ${CXXFLAGS} -o dij_ch dijkstra_ch.cc parser_gr.cc timer.cc parser_ss.cc -lm
echo "  Compiling CH (checksum mode)..."
g++ ${CXXFLAGS} -DCHECKSUM -o dij_chC dijkstra_ch.cc parser_gr.cc timer.cc parser_ss.cc -lm

# Also compile BH for reference checksums if not already built
if [ ! -f "dij_bhC" ]; then
    echo "  Compiling BH (checksum mode) for reference..."
    g++ ${CXXFLAGS} -DCHECKSUM -o dij_bhC dijkstra_bh.cc parser_gr.cc timer.cc parser_ss.cc -lm
fi

echo "  Done."

# =============================================================================
# STEP 2: Run CH on all graphs
# =============================================================================
echo ""
echo "--- Step 2: Running CH benchmarks ---"

echo "graph,preprocess_sec,shortcuts,query_ms,scans,improvements" > "$CH_CSV"
echo "graph,impl,checksums" > "$CH_CHECKSUMS"

for GRAPH in $GRAPHS; do
    GR_FILE="${DATA_DIR}/USA-road-t.${GRAPH}.gr"
    SS_FILE="${DATA_DIR}/USA-road-t.${GRAPH}.ss"
    
    echo ""
    echo "=== ${GRAPH} ==="
    
    # Check files exist
    if [ ! -f "$GR_FILE" ] || [ ! -f "$SS_FILE" ]; then
        echo "  SKIP: Missing data files for ${GRAPH}"
        continue
    fi
    
    # --- Timing run ---
    echo "  Running CH (timing)..."
    OUT_FILE="${RESULTS_DIR}/USA-road-t.${GRAPH}_ch_bench.txt"
    rm -f "$OUT_FILE"
    
    ./dij_ch "$GR_FILE" "$SS_FILE" "$OUT_FILE"
    
    # Parse output
    QUERY_MS=$(grep "^t " "$OUT_FILE" | awk '{print $2}')
    SCANS=$(grep "^v " "$OUT_FILE" | awk '{print $2}')
    IMPROVEMENTS=$(grep "^i " "$OUT_FILE" | awk '{print $2}')
    PREPROCESS=$(grep "^p " "$OUT_FILE" | awk '{print $2}')
    SHORTCUTS=$(grep "^s " "$OUT_FILE" | awk '{print $2}')
    
    echo "  Preprocess: ${PREPROCESS}s, Shortcuts: ${SHORTCUTS}"
    echo "  Query: ${QUERY_MS}ms, Scans: ${SCANS}, Improvements: ${IMPROVEMENTS}"
    
    echo "${GRAPH},${PREPROCESS},${SHORTCUTS},${QUERY_MS},${SCANS},${IMPROVEMENTS}" >> "$CH_CSV"
    
    # --- Checksum run ---
    echo "  Running CH (checksum)..."
    CH_CSUM_FILE="${RESULTS_DIR}/USA-road-t.${GRAPH}_ch_bench_C.txt"
    rm -f "$CH_CSUM_FILE"
    
    ./dij_chC "$GR_FILE" "$SS_FILE" "$CH_CSUM_FILE"
    
    # Get checksums
    CH_CSUMS=$(grep "^d " "$CH_CSUM_FILE" | awk '{print $2}' | md5sum | awk '{print $1}')
    echo "ch,${GRAPH},${CH_CSUMS}" >> "$CH_CHECKSUMS"
    
    # Compare with BH checksums
    BH_CSUM_FILE="${RESULTS_DIR}/USA-road-t.${GRAPH}_bh_bench_C.txt"
    if [ ! -f "$BH_CSUM_FILE" ]; then
        echo "  Running BH (checksum) for reference..."
        rm -f "$BH_CSUM_FILE"
        ./dij_bhC "$GR_FILE" "$SS_FILE" "$BH_CSUM_FILE"
    fi
    
    BH_CSUMS=$(grep "^d " "$BH_CSUM_FILE" | awk '{print $2}' | md5sum | awk '{print $1}')
    echo "bh,${GRAPH},${BH_CSUMS}" >> "$CH_CHECKSUMS"
    
    if [ "$CH_CSUMS" == "$BH_CSUMS" ]; then
        echo "  ✅ CORRECT: CH checksums match BH"
    else
        echo "  ❌ MISMATCH: CH=${CH_CSUMS} BH=${BH_CSUMS}"
    fi
done

# =============================================================================
# STEP 3: Summary
# =============================================================================
echo ""
echo "============================================"
echo " RESULTS SUMMARY"
echo "============================================"
echo ""
echo "--- CH Benchmark Results ---"
cat "$CH_CSV"
echo ""
echo "--- Checksum Verification ---"
cat "$CH_CHECKSUMS"
echo ""
echo "Completed: $(date)"
echo ""
echo "Output files:"
echo "  Benchmark:  $CH_CSV"
echo "  Checksums:  $CH_CHECKSUMS"
echo "  Full log:   results/ch_benchmark.log"
echo ""
echo "NOTE: CH preprocessing is expensive (minutes for large graphs)."
echo "      Query times should be MUCH faster than standard Dijkstra."
echo "      The SSSP comparison uses Dijkstra on augmented graph (with shortcuts),"
echo "      not point-to-point CH queries. This is a fair SSSP comparison."
