# Benchmarks

## Data Source

All road network benchmarks use the [DIMACS 9th Implementation Challenge](http://www.dis.uniroma1.it/challenge9/) datasets:

| Graph | Region | Nodes | Arcs |
|-------|--------|------:|-----:|
| BAY | San Francisco Bay Area | 321,270 | 800,172 |
| COL | Colorado | 435,666 | 1,057,066 |
| FLA | Florida | 1,070,376 | 2,712,798 |
| NW | Northwest USA | 1,207,945 | 2,840,208 |
| NE | Northeast USA | 1,524,453 | 3,897,636 |
| USA | Full USA | 23,947,347 | 58,333,344 |

Download `.gr` (graph) and `.ss` (source) files from the DIMACS website.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build.sh` | Build all implementations |
| `scripts/run_benchmark.sh` | Run full benchmark suite |
| `scripts/run_new_comparisons.sh` | Run 9-way comparison |
| `scripts/run_ch_benchmark.sh` | Run Contraction Hierarchies benchmark |
| `scripts/run_all_evidence.sh` | Run complete evidence collection |

## Results

Results are organized by category:

```
results/
├── road/                    # Road network comparisons
│   ├── 9way_comparison.csv  # 9-implementation comparison
│   ├── all_comparison.csv   # Full comparison data
│   ├── confidence_intervals.csv
│   ├── scalability.csv
│   └── memory_usage.csv
├── grid/                    # Grid graph results
├── compile_benchmark.csv    # Compilation time/size
├── ch_benchmark.csv         # Contraction Hierarchies
├── cache_profiling.csv      # L1/L2/L3 cache miss rates
└── variant_comparison.csv   # OMBI variant sensitivity
```

## Methodology

- **5 runs per configuration**, median reported
- **Same machine**, same compiler flags (`g++ -O3 -DNDEBUG`)
- **Checksum verification** on every run (sum of distances mod 2^62)
- **No turbo boost**, CPU frequency locked during benchmarks
