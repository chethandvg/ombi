#!/bin/bash
#
# build.sh — Build all OMBI implementations
#
# Produces binaries in bin/ directory:
#   ombi   — OMBI timing mode
#   ombiC  — OMBI checksum mode
#   + all 8 baseline Dijkstra variants (timing + checksum)
#   + Goldberg's Smart Queue (timing + checksum)
#
# Usage:
#   cd /path/to/ombi
#   chmod +x benchmarks/scripts/build.sh
#   ./benchmarks/scripts/build.sh
#
# Or simply:
#   make all

set -euo pipefail

# Navigate to project root (parent of benchmarks/scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

echo "================================================================"
echo "  OMBI — Build All Implementations"
echo "================================================================"
echo ""
echo "  Project root: ${PROJECT_ROOT}"
echo ""

# Use the Makefile
make clean 2>/dev/null || true
make all

echo ""
echo "================================================================"
echo "  All binaries built successfully!"
echo "================================================================"
echo ""
ls -la bin/
echo ""
echo "Usage:"
echo "  bin/ombi  <graph.gr> <sources.ss> <output.txt>   # OMBI timing"
echo "  bin/ombiC <graph.gr> <sources.ss> <output.txt>   # OMBI checksum"
echo "  bin/sq    <graph.gr> <sources.ss> <output.txt>   # Smart Queue timing"
echo ""
echo "Example:"
echo "  DATA=/path/to/dimacs/data"
echo "  bin/ombi \$DATA/USA-road-t.BAY.gr \$DATA/USA-road-t.BAY.ss results/BAY.txt"
