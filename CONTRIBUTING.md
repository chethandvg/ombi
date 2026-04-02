# Contributing to OMBI

Thank you for your interest in contributing to OMBI!

## How to Contribute

1. **Report Issues** — Found a bug or have a suggestion? Open an issue.
2. **Submit Pull Requests** — Fork, branch, commit, and PR.
3. **Reproduce Results** — Help verify benchmarks on different hardware.

## Development Setup

### Prerequisites
- GCC/G++ with C++17 support
- Linux/WSL environment (for DIMACS benchmark scripts)
- DIMACS road network data files (see `benchmarks/README.md`)

### Building
```bash
make -f Makefile all    # Build OMBI + all baselines
make -f Makefile clean  # Clean binaries
```

### Running Benchmarks
```bash
cd benchmarks/scripts
chmod +x *.sh
./run_benchmark.sh      # Run full benchmark suite
```

## Code Style
- C++17 standard
- 4-space indentation
- Comments for non-obvious logic
- Match Goldberg's DIMACS output format for compatibility

## License
By contributing, you agree that your contributions will be licensed under the MIT License.
