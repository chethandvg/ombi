# 🚀 Getting Started — Reproducing OMBI Benchmarks

> **Goal**: Clone this repo, build everything, run benchmarks, and verify correctness
> in under 30 minutes (excluding download time for DIMACS data).

---

## 📋 Prerequisites

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| **g++** | ≥ 7.0 (C++17 support) | `g++ --version` |
| **make** | any | `make --version` |
| **bash** | ≥ 4.0 | `bash --version` |
| **md5sum** | any (for checksums) | `md5sum --version` |

### Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| 🐧 Linux (native) | ✅ Fully tested | Primary development platform |
| 🪟 WSL2 (Windows) | ✅ Fully tested | Recommended for Windows users |
| 🍎 macOS | ⚠️ Should work | Use `brew install gcc` for g++ |
| 🪟 MSYS2/MinGW | ⚠️ Untested | Should work with g++ installed |

---

## 📥 Step 1 — Clone the Repository

```bash
git clone https://github.com/<your-username>/ombi.git
cd ombi
```

---

## 📦 Step 2 — Download DIMACS Road Network Data

OMBI benchmarks use the **9th DIMACS Implementation Challenge** road network data.

### Quick Download (5 graphs, ~500MB total)

```bash
mkdir -p data
cd data

# Download travel-time graphs (.gr) and source files (.ss)
for GRAPH in BAY COL FLA NW NE; do
    wget http://www.dis.uniroma1.it/challenge9/data/USA-road-t/USA-road-t.${GRAPH}.gr.gz
    wget http://www.dis.uniroma1.it/challenge9/data/USA-road-t/USA-road-t.${GRAPH}.ss.gz
    gunzip USA-road-t.${GRAPH}.gr.gz
    gunzip USA-road-t.${GRAPH}.ss.gz
done

cd ..
```

### Graph Sizes

| Graph | Region | Nodes | Arcs | Compressed | Uncompressed |
|-------|--------|------:|-----:|-----------:|-------------:|
| BAY | San Francisco Bay | 321,270 | 800,172 | ~8 MB | ~18 MB |
| COL | Colorado | 435,666 | 1,057,066 | ~11 MB | ~24 MB |
| FLA | Florida | 1,070,376 | 2,712,798 | ~27 MB | ~62 MB |
| NW | Northwest USA | 1,207,945 | 2,840,208 | ~29 MB | ~65 MB |
| NE | Northeast USA | 1,524,453 | 3,897,636 | ~40 MB | ~89 MB |
| USA | Full USA 🇺🇸 | 23,947,347 | 58,333,344 | ~600 MB | ~1.3 GB |

> 💡 **Tip**: Start with BAY (smallest) to verify everything works before running larger graphs.

### Alternative: Use Your Own Data

Any DIMACS-format `.gr` and `.ss` files will work. The format is:
```
c Comment lines start with 'c'
p sp <nodes> <arcs>
a <source> <target> <weight>
...
```

---

## 🔨 Step 3 — Build

```bash
# Build everything (OMBI + 8 baselines + Smart Queue)
make all

# Or build selectively:
make ombi       # Just OMBI
make baselines  # Just the 8 Dijkstra baselines
make smartq     # Just Goldberg's Smart Queue
make help       # Show all targets
```

All binaries are placed in `bin/`:

```
bin/
├── ombi          # OMBI (timing mode)
├── ombiC         # OMBI (checksum mode)
├── dij_bh        # Binary Heap Dijkstra
├── dij_4h        # 4-ary Heap Dijkstra
├── dij_fh        # Fibonacci Heap Dijkstra
├── dij_ph        # Pairing Heap Dijkstra
├── dij_dial      # Dial's Algorithm
├── dij_r1        # 1-Level Radix Heap
├── dij_r2        # 2-Level Radix Heap
├── dij_ch        # Contraction Hierarchies
├── sq            # Goldberg's Smart Queue (timing)
└── sqC           # Goldberg's Smart Queue (checksum)
```

---

## ▶️ Step 4 — Run a Quick Test

```bash
# Single graph test (BAY — takes ~30 seconds)
DATA=data   # or wherever you put the .gr/.ss files

# Timing run
bin/ombi  $DATA/USA-road-t.BAY.gr $DATA/USA-road-t.BAY.ss results/BAY_ombi.txt

# Checksum verification
bin/ombiC $DATA/USA-road-t.BAY.gr $DATA/USA-road-t.BAY.ss results/BAY_ombi_chk.txt
bin/dij_bhC $DATA/USA-road-t.BAY.gr $DATA/USA-road-t.BAY.ss results/BAY_bh_chk.txt

# Compare checksums (should be identical)
diff <(grep '^d ' results/BAY_ombi_chk.txt) <(grep '^d ' results/BAY_bh_chk.txt)
echo "Checksums match!" || echo "MISMATCH!"
```

### Expected Output (stderr)

```
c ---------------------------------------------------
c OMBI Bitmap Bucket Queue — DIMACS Challenge format
c ---------------------------------------------------
c
c Nodes:                   321270       Arcs:                 800172
c MinArcLen:                    2       MaxArcLen:              69466
c BucketWidth:                  8       (4 x MinArcLen)
c HotBuckets:               16384       BitmapWords:             256
c Trials:                     200
c Scans (ave):          321270.0     Improvements (ave):   524680.2
c Time (ave, ms):            27.50
```

---

## 📊 Step 5 — Full Benchmark Suite

```bash
# Set your data directory
export DATA_DIR=data   # or /path/to/your/dimacs/data

# Run full benchmark (all implementations × all graphs × 5 runs)
chmod +x benchmarks/scripts/run_benchmark.sh
./benchmarks/scripts/run_benchmark.sh

# Or just verify correctness (faster — no timing runs)
chmod +x benchmarks/scripts/run_checksum.sh
./benchmarks/scripts/run_checksum.sh
```

### Results

Results are written to `benchmarks/results/`:
- `benchmark_results.csv` — timing data (graph, impl, run, time_ms, scans, improvements)
- `checksum_verification.csv` — correctness verification (graph, impl, checksum_md5, match_bh)

---

## 📈 Expected Results

### Timing (median of 5 runs, milliseconds per query)

| Graph | SQ | **OMBI** | R2 | 4H | BH | R1 | Dial | PH | FH |
|-------|---:|--------:|---:|---:|---:|---:|-----:|---:|---:|
| BAY | 26.3 | **27.5** | 36.1 | 37.2 | 38.1 | 41.3 | 48.2 | 53.6 | 64.3 |
| COL | 37.3 | **39.4** | 51.7 | 52.2 | 53.2 | 57.8 | 66.7 | 74.1 | 92.2 |
| FLA | 89.7 | **101.7** | 131.2 | 135.1 | 136.3 | 149.2 | 171.1 | 191.3 | 240.1 |
| NW | 112.1 | **117.5** | 156.2 | 158.3 | 160.7 | 174.8 | 199.7 | 223.1 | 280.2 |
| NE | 143.7 | **154.9** | 203.1 | 205.2 | 209.3 | 228.1 | 260.3 | 291.2 | 365.1 |

> **Ranking**: SQ > OMBI > R2 > 4H ≈ BH > R1 > Dial > PH > FH

### Correctness

All implementations produce **identical checksums** on all 5 graphs (45/45 tests pass).

---

## 🔧 Troubleshooting

### Build Errors

| Error | Fix |
|-------|-----|
| `g++: command not found` | Install g++: `sudo apt install g++` (Ubuntu) or `brew install gcc` (macOS) |
| `error: 'uint64_t' was not declared` | Ensure g++ ≥ 7.0 with C++17 support |
| `__builtin_ctzll not found` | Use g++ or clang++ (MSVC doesn't support GCC builtins) |

### Runtime Errors

| Error | Fix |
|-------|-----|
| `ERROR: cannot open graph file` | Check DATA_DIR path and file existence |
| `Segmentation fault` | Graph file may be corrupted — re-download |
| `Checksums don't match` | Ensure you're comparing same graph; report if persistent |

### WSL2-Specific

```bash
# If data is on Windows drive:
# DATA_DIR defaults to ./data -- only set if your data is elsewhere:
# export DATA_DIR=/path/to/your/dimacs/data

# For best performance, copy data to WSL filesystem:
cp /mnt/d/path/to/data/*.gr ~/data/
cp /mnt/d/path/to/data/*.ss ~/data/
export DATA_DIR=~/data
```

---

## 📚 Further Reading

- **[docs/EVIDENCE.md](EVIDENCE.md)** — Full experimental evidence (29 sections)
- **[docs/NOVELTY_ANALYSIS.md](NOVELTY_ANALYSIS.md)** — Comparison with prior work
- **[docs/proofs/](proofs/)** — Correctness proofs
- **[src/ombi/README.md](../src/ombi/README.md)** — Algorithm details
- **[src/baselines/README.md](../src/baselines/README.md)** — Baseline implementations

---

## 📄 Citation

If you use OMBI in your research, please cite:

```bibtex
@inproceedings{ombi2025,
  title     = {OMBI: Ordered Minimum via Bitmap Indexing for Single-Source Shortest Paths},
  author    = {[Author Name]},
  booktitle = {Proceedings of [Venue]},
  year      = {2025}
}
```
