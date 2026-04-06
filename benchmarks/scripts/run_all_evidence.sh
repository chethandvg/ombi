#!/bin/bash
# shellcheck shell=bash
#
# HISTORICAL — This script references the old directory structure.
# Use run_benchmark.sh instead for the reorganized repository.
#
# run_all_evidence.sh — Master Evidence Collection Script for OMBI Paper
#
# Runs ALL remaining experiments in one go:
#   Part 1: Re-run compare_all.sh (with fixed Dial)
#   Part 2: USA full graph (23.9M nodes) on all 7 implementations
#   Part 3: Memory usage comparison (/usr/bin/time -v)
#   Part 4: Multiple runs for confidence intervals (5 runs × 5 graphs)
#   Part 5: Scalability data (time vs n, all 6 graphs)
#
# Estimated total time: 4-8 hours
#
# Usage:
#   chmod +x run_all_evidence.sh
#   nohup ./run_all_evidence.sh > results/master_evidence.log 2>&1 &
#   # or interactively:
#   ./run_all_evidence.sh 2>&1 | tee results/master_evidence.log
#

set -euo pipefail

V27_DIR="/mnt/d/Projects/Practice/Research/nexus3/C_Lang/v27-dimacs"
GOLDBERG_DIR="/mnt/d/Projects/Practice/Research/nexus3/C_Lang/ch9-1.1/solvers/mlb-dimacs"
DATA_DIR="/mnt/d/Projects/Practice/Research/nexus3/csharp/data"
RESULTS="${V27_DIR}/results"

mkdir -p "${RESULTS}"

CXXFLAGS="-std=c++17 -Wall -O3 -DNDEBUG"
COMMON_SRC="parser_gr.cc timer.cc parser_ss.cc"

GRAPHS_5=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
)

GRAPHS_6=(
    "USA-road-t.BAY"
    "USA-road-t.COL"
    "USA-road-t.FLA"
    "USA-road-t.NW"
    "USA-road-t.NE"
    "USA-road-t.USA"
)

start_total=$(date +%s)

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║   OMBI Paper — Master Evidence Collection                          ║"
echo "║                                                                    ║"
echo "║   Part 1: Re-run 7-way comparison (with fixed Dial)               ║"
echo "║   Part 2: USA full graph (23.9M nodes)                            ║"
echo "║   Part 3: Memory usage comparison                                 ║"
echo "║   Part 4: Confidence intervals (5 runs)                           ║"
echo "║   Part 5: Scalability data (6 graphs)                             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Started at: $(date)"
echo ""

# ================================================================
# PART 0: BUILD ALL BINARIES
# ================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  PART 0: BUILD ALL BINARIES                                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

cd "${V27_DIR}"

echo -n "[1/7] Binary Heap (dij_bh)... "
g++ ${CXXFLAGS} -o dij_bh dijkstra_bh.cc ${COMMON_SRC} -lm
g++ ${CXXFLAGS} -DCHECKSUM -o dij_bhC dijkstra_bh.cc ${COMMON_SRC} -lm
echo "OK"

echo -n "[2/7] 4-ary Indexed Heap (dij_4h)... "
g++ ${CXXFLAGS} -o dij_4h dijkstra_4h.cc ${COMMON_SRC} -lm
g++ ${CXXFLAGS} -DCHECKSUM -o dij_4hC dijkstra_4h.cc ${COMMON_SRC} -lm
echo "OK"

echo -n "[3/7] Fibonacci Heap (dij_fh)... "
g++ ${CXXFLAGS} -o dij_fh dijkstra_fh.cc ${COMMON_SRC} -lm
g++ ${CXXFLAGS} -DCHECKSUM -o dij_fhC dijkstra_fh.cc ${COMMON_SRC} -lm
echo "OK"

echo -n "[4/7] Pairing Heap (dij_ph)... "
g++ ${CXXFLAGS} -o dij_ph dijkstra_ph.cc ${COMMON_SRC} -lm
g++ ${CXXFLAGS} -DCHECKSUM -o dij_phC dijkstra_ph.cc ${COMMON_SRC} -lm
echo "OK"

echo -n "[5/7] Dial's Algorithm (dij_dial) [FIXED]... "
g++ ${CXXFLAGS} -o dij_dial dijkstra_dial.cc ${COMMON_SRC} -lm
g++ ${CXXFLAGS} -DCHECKSUM -o dij_dialC dijkstra_dial.cc ${COMMON_SRC} -lm
echo "OK"

echo -n "[6/7] Goldberg Smart Queue (sq)... "
cd "${GOLDBERG_DIR}"
g++ ${CXXFLAGS} -o sq main.cc smartq.cc sp.cc parser_gr.cc timer.cc parser_ss.cc -lm
g++ ${CXXFLAGS} -DCHECKSUM -o sqC main.cc smartq.cc sp.cc parser_gr.cc timer.cc parser_ss.cc -lm
echo "OK"
cd "${V27_DIR}"

echo -n "[7/7] OMBI — Bitmap Bucket Queue (ombi)... "
g++ ${CXXFLAGS} -DV27_OPT -DV27_BW_MULT=4 -o ombi main.cc v27_opt.cc ${COMMON_SRC} -lm
g++ ${CXXFLAGS} -DV27_OPT -DV27_BW_MULT=4 -DCHECKSUM -o ombiC main.cc v27_opt.cc ${COMMON_SRC} -lm
echo "OK"

echo ""
echo "All 14 binaries built successfully."
echo ""

# Implementation specs
declare -A IMPL_DIR
IMPL_DIR[bh]="${V27_DIR}"
IMPL_DIR[4h]="${V27_DIR}"
IMPL_DIR[fh]="${V27_DIR}"
IMPL_DIR[ph]="${V27_DIR}"
IMPL_DIR[dial]="${V27_DIR}"
IMPL_DIR[sq]="${GOLDBERG_DIR}"
IMPL_DIR[ombi]="${V27_DIR}"

declare -A IMPL_TBIN
IMPL_TBIN[bh]="dij_bh"
IMPL_TBIN[4h]="dij_4h"
IMPL_TBIN[fh]="dij_fh"
IMPL_TBIN[ph]="dij_ph"
IMPL_TBIN[dial]="dij_dial"
IMPL_TBIN[sq]="sq"
IMPL_TBIN[ombi]="ombi"

declare -A IMPL_CBIN
IMPL_CBIN[bh]="dij_bhC"
IMPL_CBIN[4h]="dij_4hC"
IMPL_CBIN[fh]="dij_fhC"
IMPL_CBIN[ph]="dij_phC"
IMPL_CBIN[dial]="dij_dialC"
IMPL_CBIN[sq]="sqC"
IMPL_CBIN[ombi]="ombiC"

LABELS=(bh 4h fh ph dial sq ombi)

# Helper: run a single timing experiment and extract results
# Args: $1=label $2=graph $3=output_file
run_timing() {
    local label="$1" graph="$2" outfile="$3"
    local dir="${IMPL_DIR[$label]}"
    local tbin="${IMPL_TBIN[$label]}"
    local gr="${DATA_DIR}/${graph}.gr"
    local ss="${DATA_DIR}/${graph}.ss"
    rm -f "${outfile}"
    "${dir}/${tbin}" "${gr}" "${ss}" "${outfile}" 2>/dev/null
}

# Helper: run a single checksum experiment and return MD5
# Args: $1=label $2=graph $3=output_file
run_checksum() {
    local label="$1" graph="$2" outfile="$3"
    local dir="${IMPL_DIR[$label]}"
    local cbin="${IMPL_CBIN[$label]}"
    local gr="${DATA_DIR}/${graph}.gr"
    local ss="${DATA_DIR}/${graph}.ss"
    rm -f "${outfile}"
    "${dir}/${cbin}" "${gr}" "${ss}" "${outfile}" 2>/dev/null
}

# ================================================================
# PART 1: RE-RUN 7-WAY COMPARISON (with fixed Dial)
# ================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  PART 1: 7-Way Comparison on 5 Graphs (with fixed Dial)           ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

CSV1="${RESULTS}/all_comparison.csv"
CHK1="${RESULTS}/all_checksums.csv"
echo "graph,impl,time_ms,scans,improvements,checksum_md5" > "${CSV1}"
echo "graph,impl,checksum_md5,match_bh" > "${CHK1}"

for graph in "${GRAPHS_5[@]}"; do
    gr="${DATA_DIR}/${graph}.gr"
    ss="${DATA_DIR}/${graph}.ss"

    echo "┌─ ${graph}"

    ref_checksum=""

    for label in "${LABELS[@]}"; do
        tout="${RESULTS}/${graph}_${label}.txt"
        cout="${RESULTS}/${graph}_${label}_C.txt"

        echo -n "  ${label}: "

        # Timing run
        run_timing "${label}" "${graph}" "${tout}"
        t_ms=$(grep '^t ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        scans=$(grep '^v ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        improv=$(grep '^i ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")

        # Checksum run
        run_checksum "${label}" "${graph}" "${cout}"
        chk_md5=$(grep '^d ' "${cout}" 2>/dev/null | md5sum | awk '{print $1}')

        if [ "${label}" = "bh" ]; then
            ref_checksum="${chk_md5}"
        fi

        if [ "${chk_md5}" = "${ref_checksum}" ]; then
            match="YES"
        else
            match="NO"
        fi

        printf "%8s ms  chk=%s\n" "${t_ms}" "${match}"

        echo "${graph},${label},${t_ms},${scans},${improv},${chk_md5}" >> "${CSV1}"
        echo "${graph},${label},${chk_md5},${match}" >> "${CHK1}"
    done
    echo "└─ done"
    echo ""
done

# Quick summary
echo "Part 1 checksum summary:"
for graph in "${GRAPHS_5[@]}"; do
    short="${graph#USA-road-t.}"
    fails=$(grep "^${graph}," "${CHK1}" | grep ",NO$" | wc -l)
    if [ "${fails}" -gt 0 ]; then
        echo "  ${short}: ❌ ${fails} mismatches"
    else
        echo "  ${short}: ✅ All match"
    fi
done
echo ""

# ================================================================
# PART 2: USA FULL GRAPH (23.9M nodes)
# ================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  PART 2: USA Full Graph (23.9M nodes, 58.3M arcs)                 ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

USA_GRAPH="USA-road-t.USA"
USA_GR="${DATA_DIR}/${USA_GRAPH}.gr"
USA_SS="${DATA_DIR}/${USA_GRAPH}.ss"

CSV2="${RESULTS}/usa_full_comparison.csv"
CHK2="${RESULTS}/usa_full_checksums.csv"
echo "graph,impl,time_ms,scans,improvements,checksum_md5" > "${CSV2}"
echo "graph,impl,checksum_md5,match_bh" > "${CHK2}"

if [ -f "${USA_GR}" ] && [ -f "${USA_SS}" ]; then
    echo "Graph: ${USA_GRAPH}"
    echo "Expected: ~23.9M nodes, ~58.3M arcs"
    echo ""

    # For USA, skip Fibonacci and Pairing heaps (too slow, would take 30+ min each)
    # Run: bh, 4h, dial, sq, ombi
    USA_LABELS=(bh 4h dial sq ombi)

    ref_checksum=""

    for label in "${USA_LABELS[@]}"; do
        tout="${RESULTS}/${USA_GRAPH}_${label}.txt"
        cout="${RESULTS}/${USA_GRAPH}_${label}_C.txt"

        echo -n "  ${label}: "
        start_t=$(date +%s)

        # Timing run
        run_timing "${label}" "${USA_GRAPH}" "${tout}"
        t_ms=$(grep '^t ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        scans=$(grep '^v ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        improv=$(grep '^i ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")

        # Checksum run
        run_checksum "${label}" "${USA_GRAPH}" "${cout}"
        chk_md5=$(grep '^d ' "${cout}" 2>/dev/null | md5sum | awk '{print $1}')

        if [ "${label}" = "bh" ]; then
            ref_checksum="${chk_md5}"
        fi

        if [ "${chk_md5}" = "${ref_checksum}" ]; then
            match="YES"
        else
            match="NO"
        fi

        end_t=$(date +%s)
        elapsed=$((end_t - start_t))

        printf "%10s ms  chk=%s  wall=%ds\n" "${t_ms}" "${match}" "${elapsed}"

        echo "${USA_GRAPH},${label},${t_ms},${scans},${improv},${chk_md5}" >> "${CSV2}"
        echo "${USA_GRAPH},${label},${chk_md5},${match}" >> "${CHK2}"
    done

    # Now run Fibonacci and Pairing on USA (will be slow!)
    echo ""
    echo "  Running Fibonacci and Pairing heaps on USA (expect 30-60 min each)..."
    for label in fh ph; do
        tout="${RESULTS}/${USA_GRAPH}_${label}.txt"
        cout="${RESULTS}/${USA_GRAPH}_${label}_C.txt"

        echo -n "  ${label}: "
        start_t=$(date +%s)

        # Timing run
        run_timing "${label}" "${USA_GRAPH}" "${tout}"
        t_ms=$(grep '^t ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        scans=$(grep '^v ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        improv=$(grep '^i ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")

        # Checksum run
        run_checksum "${label}" "${USA_GRAPH}" "${cout}"
        chk_md5=$(grep '^d ' "${cout}" 2>/dev/null | md5sum | awk '{print $1}')

        if [ "${chk_md5}" = "${ref_checksum}" ]; then
            match="YES"
        else
            match="NO"
        fi

        end_t=$(date +%s)
        elapsed=$((end_t - start_t))

        printf "%10s ms  chk=%s  wall=%ds\n" "${t_ms}" "${match}" "${elapsed}"

        echo "${USA_GRAPH},${label},${t_ms},${scans},${improv},${chk_md5}" >> "${CSV2}"
        echo "${USA_GRAPH},${label},${chk_md5},${match}" >> "${CHK2}"
    done

    echo ""
    echo "Part 2 checksum summary:"
    fails=$(grep "^${USA_GRAPH}," "${CHK2}" | grep ",NO$" | wc -l)
    if [ "${fails}" -gt 0 ]; then
        echo "  USA: ❌ ${fails} mismatches"
    else
        echo "  USA: ✅ All match"
    fi
else
    echo "  SKIP: USA graph files not found at ${USA_GR}"
fi
echo ""

# ================================================================
# PART 3: MEMORY USAGE COMPARISON
# ================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  PART 3: Memory Usage Comparison (Peak RSS)                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

CSV3="${RESULTS}/memory_usage.csv"
echo "graph,impl,peak_rss_kb,time_wall_s" > "${CSV3}"

# Use /usr/bin/time -v to measure peak RSS
# We'll run on 3 representative graphs: BAY (small), FLA (medium), NE (large)
MEM_GRAPHS=("USA-road-t.BAY" "USA-road-t.FLA" "USA-road-t.NE")

# Also run on USA if available
if [ -f "${USA_GR}" ]; then
    MEM_GRAPHS+=("USA-road-t.USA")
fi

for graph in "${MEM_GRAPHS[@]}"; do
    gr="${DATA_DIR}/${graph}.gr"
    ss="${DATA_DIR}/${graph}.ss"
    short="${graph#USA-road-t.}"

    if [ ! -f "${gr}" ]; then
        echo "  SKIP: ${graph} not found"
        continue
    fi

    echo "┌─ ${short}"

    for label in "${LABELS[@]}"; do
        # Skip fh/ph on USA (too slow for memory measurement)
        if [ "${graph}" = "USA-road-t.USA" ] && { [ "${label}" = "fh" ] || [ "${label}" = "ph" ]; }; then
            echo "  ${label}: SKIP (too slow for USA)"
            continue
        fi

        dir="${IMPL_DIR[$label]}"
        tbin="${IMPL_TBIN[$label]}"
        memout="${RESULTS}/${graph}_${label}_mem.txt"
        tout="${RESULTS}/${graph}_${label}_memrun.txt"
        rm -f "${tout}" "${memout}"

        echo -n "  ${label}: "

        # Run with /usr/bin/time -v
        /usr/bin/time -v "${dir}/${tbin}" "${gr}" "${ss}" "${tout}" \
            2>"${memout}" || true

        # Extract peak RSS (in KB)
        peak_rss=$(grep "Maximum resident set size" "${memout}" 2>/dev/null | awk '{print $NF}' || echo "N/A")
        wall_time=$(grep "wall clock" "${memout}" 2>/dev/null | awk '{print $NF}' || echo "N/A")

        # Convert wall time (h:mm:ss or m:ss.ss) to seconds
        if [ "${wall_time}" != "N/A" ]; then
            # Parse time format (could be "0:05.23" or "1:02:03")
            wall_secs=$(echo "${wall_time}" | awk -F: '{
                if (NF==3) print $1*3600 + $2*60 + $3;
                else if (NF==2) print $1*60 + $2;
                else print $1;
            }')
        else
            wall_secs="N/A"
        fi

        printf "peak_rss=%s KB  wall=%s\n" "${peak_rss}" "${wall_time}"

        echo "${graph},${label},${peak_rss},${wall_secs}" >> "${CSV3}"
    done
    echo "└─ done"
    echo ""
done

echo "Memory results: ${CSV3}"
echo ""

# ================================================================
# PART 4: CONFIDENCE INTERVALS (5 runs × 5 graphs)
# ================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  PART 4: Confidence Intervals (5 runs per implementation)          ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

CSV4="${RESULTS}/confidence_intervals.csv"
echo "graph,impl,run,time_ms" > "${CSV4}"

NUM_RUNS=5

# Run only the 4 key implementations for CI: bh, sq, ombi, dial
CI_LABELS=(bh dial sq ombi)

for graph in "${GRAPHS_5[@]}"; do
    short="${graph#USA-road-t.}"
    echo "┌─ ${short}"

    for label in "${CI_LABELS[@]}"; do
        echo -n "  ${label}: "
        for run in $(seq 1 ${NUM_RUNS}); do
            tout="${RESULTS}/${graph}_${label}_run${run}.txt"
            run_timing "${label}" "${graph}" "${tout}"
            t_ms=$(grep '^t ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
            echo "${graph},${label},${run},${t_ms}" >> "${CSV4}"
            echo -n "${t_ms} "
        done
        echo ""
    done
    echo "└─ done"
    echo ""
done

echo "Confidence interval data: ${CSV4}"
echo ""

# ================================================================
# PART 5: SCALABILITY DATA (6 graphs including USA)
# ================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  PART 5: Scalability Data (all 6 graphs, for log-log plots)        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

CSV5="${RESULTS}/scalability.csv"
echo "graph,nodes,arcs,impl,time_ms,scans,improvements" > "${CSV5}"

# Node counts for each graph (hardcoded for CSV)
declare -A GRAPH_NODES
GRAPH_NODES[USA-road-t.BAY]=321270
GRAPH_NODES[USA-road-t.COL]=435666
GRAPH_NODES[USA-road-t.FLA]=1070376
GRAPH_NODES[USA-road-t.NW]=1207945
GRAPH_NODES[USA-road-t.NE]=1524453
GRAPH_NODES[USA-road-t.USA]=23947347

declare -A GRAPH_ARCS
GRAPH_ARCS[USA-road-t.BAY]=800172
GRAPH_ARCS[USA-road-t.COL]=1057066
GRAPH_ARCS[USA-road-t.FLA]=2712798
GRAPH_ARCS[USA-road-t.NW]=2840208
GRAPH_ARCS[USA-road-t.NE]=3897636
GRAPH_ARCS[USA-road-t.USA]=58333344

# For scalability, run bh, sq, ombi on all 6 graphs
SCALE_LABELS=(bh sq ombi)

for graph in "${GRAPHS_6[@]}"; do
    gr="${DATA_DIR}/${graph}.gr"
    ss="${DATA_DIR}/${graph}.ss"
    short="${graph#USA-road-t.}"

    if [ ! -f "${gr}" ] || [ ! -f "${ss}" ]; then
        echo "  SKIP: ${graph} not found"
        continue
    fi

    nodes="${GRAPH_NODES[$graph]}"
    arcs="${GRAPH_ARCS[$graph]}"

    echo -n "  ${short} (${nodes} nodes): "

    for label in "${SCALE_LABELS[@]}"; do
        tout="${RESULTS}/${graph}_${label}_scale.txt"
        run_timing "${label}" "${graph}" "${tout}"
        t_ms=$(grep '^t ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        scans=$(grep '^v ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        improv=$(grep '^i ' "${tout}" 2>/dev/null | awk '{print $2}' || echo "N/A")
        echo "${graph},${nodes},${arcs},${label},${t_ms},${scans},${improv}" >> "${CSV5}"
        echo -n "${label}=${t_ms} "
    done
    echo ""
done

echo ""
echo "Scalability data: ${CSV5}"
echo ""

# ================================================================
# FINAL SUMMARY
# ================================================================
end_total=$(date +%s)
elapsed_total=$((end_total - start_total))
elapsed_min=$((elapsed_total / 60))
elapsed_sec=$((elapsed_total % 60))

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  COMPLETE — All Evidence Collected                                 ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total time: ${elapsed_min}m ${elapsed_sec}s"
echo ""
echo "Output files:"
echo "  1. ${CSV1}         — 7-way comparison (5 graphs)"
echo "  2. ${CHK1}         — Checksum verification (5 graphs)"
echo "  3. ${CSV2}   — USA full graph comparison"
echo "  4. ${CHK2}   — USA checksum verification"
echo "  5. ${CSV3}          — Memory usage (peak RSS)"
echo "  6. ${CSV4}   — Confidence intervals (5 runs)"
echo "  7. ${CSV5}             — Scalability data (6 graphs)"
echo ""
echo "Finished at: $(date)"
