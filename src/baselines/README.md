# Baseline Implementations

Eight Dijkstra implementations used for fair comparison against OMBI.  
All share the same DIMACS I/O infrastructure and compiler flags.

## Implementations

| File | Algorithm | Time Complexity | Notes |
|------|-----------|----------------|-------|
| `dijkstra_bh.cc` | Binary Heap | O((n+m) log n) | Standard textbook baseline |
| `dijkstra_4h.cc` | 4-ary Heap | O((n+m) log₄ n) | Cache-friendlier than binary |
| `dijkstra_fh.cc` | Fibonacci Heap | O(n log n + m) | Theoretical optimum; poor cache |
| `dijkstra_ph.cc` | Pairing Heap | O(n log n + m) amortized | Simpler than Fibonacci |
| `dijkstra_dial.cc` | Dial's Algorithm | O(n·C + m) | Linear scan bucket queue |
| `dijkstra_radix1.cc` | 1-Level Radix Heap | O((n+m)·√(log C)) | Single-level radix decomposition |
| `dijkstra_radix2.cc` | 2-Level Radix Heap | O((n+m)·log^(1/3) C) | Two-level radix decomposition |
| `dijkstra_ch.cc` | Contraction Hierarchies | Varies | Preprocessing + bidirectional query |

## Smart Queue (Goldberg)

The `smartq/` subdirectory contains Andrew V. Goldberg's Smart Queue — the **fastest known** SSSP implementation for road networks. It serves as the primary comparison target.

⚠️ **License:** Smart Queue is Copyright (c) Andrew V. Goldberg. See `smartq/COPYRIGHT` for terms.
