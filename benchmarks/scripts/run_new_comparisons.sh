#!/bin/bash
#
# HISTORICAL — This script references the old directory structure.
# Use run_benchmark.sh instead for the reorganized repository.
#
# =============================================================================
# OMBI Evidence: New Comparison Metrics (Session 29)
# =============================================================================
# Run from: /mnt/d/Projects/Practice/Research/nexus3/C_Lang/v27-dimacs
# Usage:    bash run_new_comparisons.sh 2>&1 | tee results/new_comparisons.log
# =============================================================================

set -e

CXXFLAGS="-std=c++17 -Wall -O3 -DNDEBUG"
DATA_DIR="/mnt/d/Projects/Practice/Research/nexus3/csharp/data"
SQ_DIR="../ch9-1.1/solvers/mlb-dimacs"
RESULTS="results/new_comparisons.csv"
COMPILE_RESULTS="results/compile_benchmark.csv"
CACHE_RESULTS="results/cache_profiling.csv"

GRAPHS="BAY COL FLA NW NE"

echo "============================================"
echo " OMBI Evidence: New Comparison Metrics"
echo " Started: $(date)"
echo "============================================"

# =============================================================================
# PART 1: Compilation Time & Binary Size
# =============================================================================
echo ""
echo "============================================"
echo " PART 1: Compilation Time & Binary Size"
echo "============================================"

echo "impl,compile_time_ms,binary_size_bytes,binary_size_kb" > "$COMPILE_RESULTS"

# Clean any previous binaries
rm -f dij_bh dij_4h dij_fh dij_ph dij_dial dij_r1 dij_r2 ombi_bench sq_bench

compile_and_measure() {
    local name=$1
    shift
    local cmd="$@"
    
    # Time compilation (3 runs, take median)
    local times=()
    for run in 1 2 3; do
        rm -f "${name}"
        local start=$(date +%s%N)
        eval "$cmd"
        local end=$(date +%s%N)
        local elapsed=$(( (end - start) / 1000000 ))
        times+=($elapsed)
    done
    
    # Sort and take median
    IFS=$'\n' sorted=($(sort -n <<<"${times[*]}")); unset IFS
    local median=${sorted[1]}
    
    # Get binary size
    local size=$(stat -c%s "${name}" 2>/dev/null || echo 0)
    local size_kb=$(( size / 1024 ))
    
    echo "${name},${median},${size},${size_kb}"
    echo "${name},${median},${size},${size_kb}" >> "$COMPILE_RESULTS"
    echo "  ${name}: ${median}ms compile, ${size_kb}KB binary"
}

echo "Compiling all implementations (3 runs each for median)..."

compile_and_measure "dij_bh" \
    "g++ ${CXXFLAGS} -o dij_bh dijkstra_bh.cc parser_gr.cc timer.cc parser_ss.cc -lm"

compile_and_measure "dij_4h" \
    "g++ ${CXXFLAGS} -o dij_4h dijkstra_4h.cc parser_gr.cc timer.cc parser_ss.cc -lm"

compile_and_measure "dij_fh" \
    "g++ ${CXXFLAGS} -o dij_fh dijkstra_fh.cc parser_gr.cc timer.cc parser_ss.cc -lm"

compile_and_measure "dij_ph" \
    "g++ ${CXXFLAGS} -o dij_ph dijkstra_ph.cc parser_gr.cc timer.cc parser_ss.cc -lm"

compile_and_measure "dij_dial" \
    "g++ ${CXXFLAGS} -o dij_dial dijkstra_dial.cc parser_gr.cc timer.cc parser_ss.cc -lm"

compile_and_measure "dij_r1" \
    "g++ ${CXXFLAGS} -o dij_r1 dijkstra_radix1.cc parser_gr.cc timer.cc parser_ss.cc -lm"

compile_and_measure "dij_r2" \
    "g++ ${CXXFLAGS} -o dij_r2 dijkstra_radix2.cc parser_gr.cc timer.cc parser_ss.cc -lm"

compile_and_measure "ombi_bench" \
    "g++ ${CXXFLAGS} -DV27_OPT -DV27_BW_MULT=4 -o ombi_bench main.cc v27_opt.cc parser_gr.cc timer.cc parser_ss.cc -lm"

# SQ compilation (from its own directory)
pushd "$SQ_DIR" > /dev/null
compile_and_measure "sq" \
    "g++ ${CXXFLAGS} -o sq main.cc smartq.cc sp.cc parser_gr.cc timer.cc parser_ss.cc -lm"
popd > /dev/null
# Copy SQ binary for cache profiling
cp "${SQ_DIR}/sq" sq_bench 2>/dev/null || true

echo ""
echo "Compilation results saved to: $COMPILE_RESULTS"

# =============================================================================
# PART 2: Cache Miss Profiling (perf stat)
# =============================================================================
echo ""
echo "============================================"
echo " PART 2: Cache Miss Profiling (perf stat)"
echo "============================================"

# Check if perf is available
if ! command -v perf &> /dev/null; then
    echo "WARNING: 'perf' not found. Skipping cache profiling."
    echo "Install with: sudo apt install linux-tools-generic linux-tools-$(uname -r)"
    echo "If in WSL2, you may need to build perf from source."
    SKIP_PERF=1
else
    SKIP_PERF=0
fi

if [ "$SKIP_PERF" -eq 0 ]; then
    echo "impl,graph,cycles,instructions,ipc,L1_misses,LLC_misses,LLC_miss_rate,branch_misses" > "$CACHE_RESULTS"
    
    # Use BAY (smallest, fastest) for cache profiling
    GRAPH="BAY"
    GR_FILE="${DATA_DIR}/USA-road-t.${GRAPH}.gr"
    SS_FILE="${DATA_DIR}/USA-road-t.${GRAPH}.ss"
    
    echo "Running cache profiling on ${GRAPH}..."
    
    profile_impl() {
        local name=$1
        local binary=$2
        local extra_args=$3
        
        echo "  Profiling ${name}..."
        
        # Run perf stat
        local output
        output=$(perf stat -e cycles,instructions,L1-dcache-load-misses,LLC-load-misses,LLC-loads,branch-misses \
            ${binary} ${GR_FILE} ${SS_FILE} /dev/null ${extra_args} 2>&1)
        
        # Parse perf output
        local cycles=$(echo "$output" | grep "cycles" | head -1 | awk '{print $1}' | tr -d ',')
        local instructions=$(echo "$output" | grep "instructions" | head -1 | awk '{print $1}' | tr -d ',')
        local ipc=$(echo "$output" | grep "instructions" | head -1 | grep -oP '[\d.]+\s+insn per cycle' | awk '{print $1}')
        local l1_misses=$(echo "$output" | grep "L1-dcache-load-misses" | awk '{print $1}' | tr -d ',')
        local llc_misses=$(echo "$output" | grep "LLC-load-misses" | awk '{print $1}' | tr -d ',')
        local llc_loads=$(echo "$output" | grep "LLC-loads" | awk '{print $1}' | tr -d ',')
        local branch_misses=$(echo "$output" | grep "branch-misses" | awk '{print $1}' | tr -d ',')
        
        # Calculate LLC miss rate
        local llc_rate="N/A"
        if [ -n "$llc_loads" ] && [ "$llc_loads" != "0" ]; then
            llc_rate=$(echo "scale=2; $llc_misses * 100 / $llc_loads" | bc 2>/dev/null || echo "N/A")
        fi
        
        echo "${name},${GRAPH},${cycles},${instructions},${ipc},${l1_misses},${llc_misses},${llc_rate}%,${branch_misses}" >> "$CACHE_RESULTS"
        echo "    cycles=${cycles} instr=${instructions} IPC=${ipc} L1miss=${l1_misses} LLCmiss=${llc_misses} (${llc_rate}%)"
    }
    
    profile_impl "bh" "./dij_bh" ""
    profile_impl "4h" "./dij_4h" ""
    profile_impl "fh" "./dij_fh" ""
    profile_impl "ph" "./dij_ph" ""
    profile_impl "dial" "./dij_dial" ""
    profile_impl "r1" "./dij_r1" ""
    profile_impl "r2" "./dij_r2" ""
    profile_impl "ombi" "./ombi_bench" ""
    
    # SQ uses different argument format
    if [ -f "sq_bench" ]; then
        echo "  Profiling sq..."
        output=$(perf stat -e cycles,instructions,L1-dcache-load-misses,LLC-load-misses,LLC-loads,branch-misses \
            ./sq_bench ${GR_FILE} ${SS_FILE} /dev/null 2>&1)
        
        cycles=$(echo "$output" | grep "cycles" | head -1 | awk '{print $1}' | tr -d ',')
        instructions=$(echo "$output" | grep "instructions" | head -1 | awk '{print $1}' | tr -d ',')
        ipc=$(echo "$output" | grep "instructions" | head -1 | grep -oP '[\d.]+\s+insn per cycle' | awk '{print $1}')
        l1_misses=$(echo "$output" | grep "L1-dcache-load-misses" | awk '{print $1}' | tr -d ',')
        llc_misses=$(echo "$output" | grep "LLC-load-misses" | awk '{print $1}' | tr -d ',')
        llc_loads=$(echo "$output" | grep "LLC-loads" | awk '{print $1}' | tr -d ',')
        branch_misses=$(echo "$output" | grep "branch-misses" | awk '{print $1}' | tr -d ',')
        
        llc_rate="N/A"
        if [ -n "$llc_loads" ] && [ "$llc_loads" != "0" ]; then
            llc_rate=$(echo "scale=2; $llc_misses * 100 / $llc_loads" | bc 2>/dev/null || echo "N/A")
        fi
        
        echo "sq,${GRAPH},${cycles},${instructions},${ipc},${l1_misses},${llc_misses},${llc_rate}%,${branch_misses}" >> "$CACHE_RESULTS"
        echo "    cycles=${cycles} instr=${instructions} IPC=${ipc} L1miss=${l1_misses} LLCmiss=${llc_misses} (${llc_rate}%)"
    fi
    
    echo ""
    echo "Cache profiling results saved to: $CACHE_RESULTS"
else
    echo ""
    echo "ALTERNATIVE: If perf is not available, try:"
    echo "  sudo perf stat -e cycles,instructions,L1-dcache-load-misses,LLC-load-misses ./ombi_bench ${DATA_DIR}/USA-road-t.BAY.gr ${DATA_DIR}/USA-road-t.BAY.ss /dev/null"
    echo ""
    echo "Or use valgrind --tool=cachegrind:"
    echo "  valgrind --tool=cachegrind ./ombi_bench ${DATA_DIR}/USA-road-t.BAY.gr ${DATA_DIR}/USA-road-t.BAY.ss /dev/null"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================================"
echo " SUMMARY"
echo "============================================"
echo "Completed: $(date)"
echo ""
echo "Output files:"
echo "  Compilation:     $COMPILE_RESULTS"
if [ "$SKIP_PERF" -eq 0 ]; then
    echo "  Cache profiling: $CACHE_RESULTS"
fi
echo "  Full log:        results/new_comparisons.log"
echo ""
echo "Next steps:"
echo "  1. Review results/compile_benchmark.csv"
echo "  2. Review results/cache_profiling.csv (if perf available)"
echo "  3. Share results with Krutaka for EVIDENCE.md update"
