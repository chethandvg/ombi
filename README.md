<p align="center">
  <h1 align="center">🔬 OMBI</h1>
  <p align="center">
    <strong>Ordered Minimum via Bitmap Indexing</strong><br>
    A bitmap-indexed bucket queue for Single-Source Shortest Paths
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/language-C%2B%2B17-blue.svg" alt="C++17">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT License">
  <img src="https://img.shields.io/badge/DIMACS-9th%20Challenge-orange.svg" alt="DIMACS 9th Challenge">
  <img src="https://img.shields.io/badge/correctness-45%2F45%20✓-brightgreen.svg" alt="Correctness Verified">
  <img src="https://img.shields.io/badge/baselines-9%20implementations-purple.svg" alt="9 Baselines">
</p>

---

## 📖 Overview

OMBI is a novel priority queue for Dijkstra's algorithm that replaces linear bucket scanning with **bitmap-indexed minimum extraction**. It uses a 256-word (2 KB) bitmap over 16,384 hot buckets, enabling O(1) amortized minimum finding via hardware `TZCNT` instructions.

### Key Idea

Traditional bucket queues (like Dial's algorithm) scan linearly for the minimum non-empty bucket — O(C) worst case. OMBI maintains a **bitmap** where bit `i` is set iff bucket `i` is non-empty. Finding the minimum becomes a bitmap scan: **one 64-bit word check + TZCNT** = ~1–4 cycles.

```
Traditional Dial:  Scan bucket[0], bucket[1], ..., bucket[k] → O(C)
OMBI:              bitmap[word] → TZCNT → bucket index           → O(1) amortized
```

## 🏗️ Architecture

```
ombi/
├── src/
│   ├── ombi/              # Core OMBI algorithm
│   │   ├── ombi.h         # Header: BEntry, ColdEntry, bitmap, hot buckets
│   │   ├── ombi.cc        # Implementation: sssp(), extractFirstLive(), addToBucket()
│   │   ├── main.cc        # DIMACS driver (reads .gr/.ss, runs SSSP, prints checksum)
│   │   ├── ombi_opt.h/cc  # Variant: bucket-width = 1 × minArcLen
│   │   └── ombi_opt2.h/cc # Variant: bucket-width = 2 × minArcLen
│   ├── baselines/         # 8 baseline Dijkstra implementations
│   │   ├── dijkstra_bh.cc    # Binary Heap
│   │   ├── dijkstra_4h.cc    # 4-ary Heap
│   │   ├── dijkstra_fh.cc    # Fibonacci Heap
│   │   ├── dijkstra_ph.cc    # Pairing Heap
│   │   ├── dijkstra_dial.cc  # Dial's Algorithm
│   │   ├── dijkstra_radix1.cc # 1-Level Radix Heap
│   │   ├── dijkstra_radix2.cc # 2-Level Radix Heap
│   │   ├── dijkstra_ch.cc    # Contraction Hierarchies
│   │   └── smartq/           # Goldberg's Smart Queue (DIMACS reference)
│   ├── infrastructure/    # Shared: DIMACS parser, timer, CSR graph
│   └── tools/             # Grid graph generator
├── benchmarks/
│   ├── scripts/           # Benchmark automation shell scripts
│   └── results/           # CSV results: road networks, grids, compilation
├── docs/                  # Evidence, proofs, analysis
│   ├── proofs/            # Formal proofs (LIFO, FIFO, non-monotonicity)
│   └── data/              # Raw CSV data for figure generation
└── paper/                 # Paper outline, figure specs, plot generation
```

## 📊 Benchmark Results

All benchmarks run on the same machine under identical conditions:  
**Compiler:** `g++ -std=c++17 -O3 -DNDEBUG` | **Data:** DIMACS 9th Challenge road networks

### Road Network Performance (median of 5 runs, milliseconds)

| Graph | Nodes | Arcs | SQ | **OMBI** | R2 | 4H | BH | R1 | Dial | PH | FH |
|-------|------:|-----:|---:|-------:|---:|---:|---:|---:|-----:|---:|---:|
| **BAY** | 321K | 800K | **26.3** | 27.5 | 30.3 | 32.2 | 32.3 | 34.3 | 36.3 | 43.2 | 55.5 |
| **COL** | 436K | 1.1M | **37.3** | 39.4 | 42.9 | 45.3 | 46.0 | 49.2 | 51.2 | 61.3 | 78.9 |
| **FLA** | 1.1M | 2.7M | **89.7** | 101.7 | 104.2 | 110.3 | 113.0 | 116.3 | 120.2 | 153.2 | 200.1 |
| **NW** | 1.2M | 2.8M | **112.1** | 117.5 | 122.0 | 127.3 | 128.1 | 135.2 | 142.3 | 173.2 | 222.1 |
| **NE** | 1.5M | 3.9M | **143.7** | 154.9 | 159.0 | 166.2 | 168.3 | 176.3 | 185.2 | 221.3 | 282.1 |

### Overall Ranking

```
SQ > OMBI > R2 > 4H ≈ BH > R1 > Dial > PH > FH
```

> **OMBI ranks #2** across all road networks, within 5–13% of Goldberg's Smart Queue.
> This is notable because SQ uses multi-level bucket decomposition while OMBI uses a simpler single-level bitmap design.

### Correctness

✅ **45/45 checksum matches** across all 9 implementations × 5 road networks.  
All implementations produce identical distance checksums (`sum of reachable distances mod 2^62`).

## 🔧 Algorithm Details

### Parameters
| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `HOT_BUCKETS` | 16,384 (2^14) | Fits bitmap in 2 KB (L1 cache) |
| `BMP_WORDS` | 256 | 16,384 / 64 bits per word |
| `bucket_width` | 4 × min_arc_weight | Balances bucket count vs. overflow rate |
| Extraction | LIFO | Avoids FIFO overhead; correctness preserved |
| Cold overflow | `std::priority_queue` | Handles distances beyond hot range |
| Lazy init | Generation counter | O(1) reset between SSSP calls |

### How It Works

1. **Relax edge (u,v):** Compute `new_dist = dist[u] + weight(u,v)`
2. **Bucket assignment:** `bucket = (new_dist / bucket_width) & MASK`
3. **Bitmap update:** Set `bitmap[bucket >> 6] |= (1ULL << (bucket & 63))`
4. **Extract minimum:** Scan bitmap for first set bit → `TZCNT` → bucket index
5. **Cold drain:** When hot buckets empty, drain from `std::priority_queue`

## 🚀 Quick Start

### Prerequisites
- G++ with C++17 support
- Linux or WSL
- [DIMACS road network files](http://www.dis.uniroma1.it/challenge9/download.shtml)

### Build
```bash
# Build OMBI
g++ -std=c++17 -O3 -DNDEBUG -o ombi src/ombi/ombi.cc src/ombi/main.cc \
    src/infrastructure/parser_gr.cc src/infrastructure/parser_ss.cc \
    src/infrastructure/timer.cc -lm

# Build a baseline (e.g., Binary Heap)
g++ -std=c++17 -O3 -DNDEBUG -o dij_bh src/baselines/dijkstra_bh.cc \
    src/infrastructure/parser_gr.cc src/infrastructure/parser_ss.cc \
    src/infrastructure/timer.cc -lm
```

### Run
```bash
# Single-source shortest paths on Bay Area road network
./ombi path/to/USA-road-t.BAY.gr path/to/USA-road-t.BAY.ss

# Output: timing (ms) and distance checksum for verification
```

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [`docs/EVIDENCE.md`](docs/EVIDENCE.md) | Complete experimental evidence (29 sections, 1700+ lines) |
| [`docs/NOVELTY_ANALYSIS.md`](docs/NOVELTY_ANALYSIS.md) | Novelty analysis and literature positioning |
| [`docs/EXPLAINED_SIMPLE.md`](docs/EXPLAINED_SIMPLE.md) | Plain-English algorithm explanation |
| [`docs/proofs/`](docs/proofs/) | Formal proofs: LIFO correctness, FIFO analysis, non-monotonicity |
| [`paper/PAPER_OUTLINE.md`](paper/PAPER_OUTLINE.md) | Working paper outline (target: ALENEX/SEA) |
| [`benchmarks/results/`](benchmarks/results/) | All benchmark CSV data |

## 🎯 Research Context

This work explores the design space of bucket-queue Dijkstra variants. Key findings:

1. **Bitmap indexing is competitive** — A simple 2 KB bitmap achieves performance within 5–13% of Goldberg's multi-level Smart Queue
2. **The error function is non-monotonic** — Bucket-width multiplier does not monotonically affect performance (see proofs)
3. **LIFO extraction is safe** — Correctness is preserved; no FIFO ordering needed
4. **Cache residency matters** — The 2 KB bitmap fits entirely in L1 cache, explaining the consistent performance

### Comparison with Goldberg's Smart Queue

| Aspect | Smart Queue (SQ) | OMBI |
|--------|-----------------|------|
| **Design** | Multi-level bucket decomposition | Single-level bitmap + cold PQ |
| **Complexity** | ~1000 LOC, sophisticated | ~400 LOC, simple |
| **Performance** | #1 (fastest) | #2 (within 5–13%) |
| **Memory** | Multi-level arrays | 2 KB bitmap + hot buckets |
| **Key insight** | Hierarchical bucket refinement | Hardware TZCNT for bitmap scan |

## 📄 License

This project is licensed under the MIT License — see [`LICENSE`](LICENSE) for details.

**Note:** The Smart Queue implementation in `src/baselines/smartq/` is Copyright (c) Andrew V. Goldberg and is included for benchmark comparison only. See `src/baselines/smartq/COPYRIGHT` for its license terms.

## 🙏 Acknowledgments

- **Andrew V. Goldberg** — Smart Queue reference implementation and DIMACS benchmark framework
- **DIMACS 9th Implementation Challenge** — Standardized road network test data
- The broader shortest-paths research community
