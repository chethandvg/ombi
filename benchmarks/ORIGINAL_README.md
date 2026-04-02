# V27: Bitmap-Accelerated Bucket Queue SSSP

> C++ port of GravityV27.cs for DIMACS Challenge benchmarking  
> **9 implementations compared** — all correct on 5 road networks (45/45 ✅)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│  V27 Bucket Queue (Single-Level + Cold Overflow)     │
├─────────────────────────────────────────────────────┤
│                                                     │
│  HOT ZONE: 16,384 circular buckets                  │
│  ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐         │
│  │B0│B1│B2│  │  │  │  │  │  │  │  │  │Bn│ ← AoS   │
│  └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘         │
│  bucket_width = 4 × min_arc_weight                  │
│                                                     │
│  BITMAP: 256 × 64-bit words (2KB → L1 cache)       │
│  ┌────────────────────────────────────────┐         │
│  │ TZCNT scan: skip 64 empty buckets/op  │         │
│  └────────────────────────────────────────┘         │
│                                                     │
│  COLD ZONE: std::priority_queue (min-heap)          │
│  ┌────────────────────────────────────────┐         │
│  │ Overflow for dist > hot window end     │         │
│  └────────────────────────────────────────┘         │
│                                                     │
│  Extraction: LIFO (from bucket array end)           │
│  Lazy deletion: generation counter per vertex       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## 🔑 Key Innovations vs Goldberg's Smart Queue

| Feature | Goldberg SQ | V27 (OMBI) |
|---------|------------|------------|
| Bucket width | ~w_min (log₂-based) | **4 × w_min** (provably correct) |
| Levels | Multi-level (2+) | Single-level + cold PQ |
| Empty scan | Linear scan | **TZCNT bitmap** (64× faster) |
| Node storage | Doubly-linked lists | **Dynamic arrays** (cache-friendly) |
| F set (caliber) | Yes | No (simpler) |
| Initialization | Per-node O(n) | **Generation counter** O(1) |

## 📦 Build (WSL/Linux)

```bash
# Quick build
chmod +x build.sh
./build.sh

# Or use make
make -f Makefile.wsl all
```

### Binaries Produced

| Binary | Description |
|--------|-------------|
| `v27` | OMBI timing mode |
| `v27C` | OMBI checksum mode |
| `dij_bh` / `dij_bh_C` | Binary heap (timing / checksum) |
| `dij_4h` / `dij_4h_C` | 4-ary heap (timing / checksum) |
| `dij_fh` / `dij_fh_C` | Fibonacci heap (timing / checksum) |
| `dij_ph` / `dij_ph_C` | Pairing heap (timing / checksum) |
| `dij_dial` / `dij_dial_C` | Dial's algorithm — **fixed** (timing / checksum) |
| `dij_r1` / `dij_r1_C` | 1-level radix heap (timing / checksum) |
| `dij_r2` / `dij_r2_C` | 2-level radix heap — **v3 circular fix** (timing / checksum) |
| `sq` / `sq_C` | Goldberg Smart Queue (timing / checksum) |
| `gen_grid` | Grid graph generator |

## 🚀 Usage

```bash
DATA=/mnt/d/Projects/Practice/Research/nexus3/csharp/data

# Timing run
./v27 $DATA/USA-road-t.BAY.gr $DATA/USA-road-t.BAY.ss results/BAY.txt

# Checksum verification
./v27C $DATA/USA-road-t.BAY.gr $DATA/USA-road-t.BAY.ss results/BAY_chk.txt

# Full benchmark (all graphs, 3 runs each)
chmod +x run_benchmark.sh
./run_benchmark.sh
```

## 📊 9-Way Performance Comparison (Road Networks)

All 9 implementations, 100 queries each, average ms per SSSP query:

| Graph | bh | 4h | fh | ph | dial | r1 | r2 | sq | ombi |
|-------|----:|----:|-----:|-----:|------:|-----:|-----:|-----:|------:|
| **BAY** | 34.09 | 33.12 | 80.96 | 60.49 | 47.12 | 45.51 | 31.72 | **26.28** | 27.52 |
| **COL** | 46.57 | 45.09 | 112.59 | 81.86 | 84.76 | 61.29 | 56.65 | **37.34** | 39.43 |
| **FLA** | 121.06 | 118.44 | 286.97 | 218.54 | 199.10 | 156.98 | 109.46 | **89.71** | 101.66 |
| **NW** | 142.56 | 141.17 | 350.36 | 273.74 | 211.49 | 180.16 | 130.79 | **112.13** | 117.50 |
| **NE** | 194.03 | 195.44 | 486.47 | 389.75 | 210.63 | 235.20 | 146.49 | **143.74** | 154.91 |

**Ranking:** SQ > OMBI > R2 > 4H ≈ BH > R1 > Dial > PH > FH

**Correctness:** 45/45 ✅ (all 9 implementations match on all 5 graphs)

## 📊 Output Format

Matches Goldberg's DIMACS format exactly:

```
# stdout
p res ss v27

# output file
f <graph_file> <aux_file>
g <nodes> <arcs> <min_weight> <max_weight>
t <avg_time_ms>
v <avg_scans>
i <avg_improvements>

# checksum mode adds per-source:
d <checksum>
```

## 📁 Files

### Core Algorithm

| File | Description |
|------|-------------|
| `v27.h` | V27 (OMBI) queue class header |
| `v27.cc` | V27 queue implementation (core algorithm) |
| `main.cc` | DIMACS-compatible driver |
| `nodearc_v27.h` | Node/Arc structs + CSR conversion |

### Comparison Implementations

| File | Description |
|------|-------------|
| `dijkstra_bh.cc` | Binary heap (std::priority_queue, lazy deletion) |
| `dijkstra_4h.cc` | 4-ary indexed heap with decrease-key |
| `dijkstra_fh.cc` | Fibonacci heap with decrease-key |
| `dijkstra_ph.cc` | Pairing heap with decrease-key |
| `dijkstra_dial.cc` | Dial's algorithm (bw=1, fixed circular bucket stale handling) |
| `dijkstra_radix1.cc` | 1-level radix heap (Ahuja et al. 1990) |
| `dijkstra_radix2.cc` | 2-level radix heap (v3 — absolute circular indexing) |
| `smartq/` | Goldberg's Smart Queue (from DIMACS reference) |

### Infrastructure

| File | Description |
|------|-------------|
| `gen_grid.cc` | Grid graph generator (4-connected, random weights) |
| `parser_gr.cc` | DIMACS graph parser (from Goldberg) |
| `parser_ss.cc` | DIMACS source parser (from Goldberg) |
| `timer.cc` | CPU timer using getrusage (from Goldberg) |
| `build.sh` | Build script for all binaries |
| `run_full_experiment_v2.sh` | Full experiment script (Parts 0-5) |

## 🔬 Correctness

The wider bucket width (4 × w_min) is provably correct for integer-weight graphs:
- Within a bucket, distances differ by at most `bw - 1 = 4*w_min - 1`
- LIFO extraction may process vertices out of order within a bucket
- But by the time we advance past a bucket, all vertices in it have been
  correctly relaxed (re-relaxation fixes any temporary errors)
- Verified on all 6 DIMACS road networks (BAY through USA, 24M vertices)
  with zero errors across 31M+ test cases

### R2 Bug Fix (v3)

The 2-level radix heap had a critical bug in the original offset-based design:
when `baseDist` shifted during redistribution, old coarse entries became
misaligned. Fixed with **absolute circular indexing** — fine bucket = `d % B1`,
coarse bucket = `(d / B1) % B2`, with a monotonically non-decreasing `scanPos`.

## 📖 Reference

Based on GravityV27.cs from the nexus3 research project.
See `docs/PAPER_OUTLINE.md` for the full paper.
See `docs/EVIDENCE.md` for comprehensive experimental evidence (15 comparisons).
