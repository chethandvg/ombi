# Source Code

## Directory Structure

```
src/
├── ombi/              # Core OMBI algorithm (the novel contribution)
├── baselines/         # 8 comparison implementations + Goldberg's Smart Queue
├── infrastructure/    # Shared code: DIMACS parsers, timer, CSR graph
└── tools/             # Utility programs (grid graph generator)
```

## Build

All implementations use the same compiler flags for fair comparison:

```bash
g++ -std=c++17 -Wall -O3 -DNDEBUG -o <binary> <sources> -lm
```

See the root `Makefile` for all build targets.
