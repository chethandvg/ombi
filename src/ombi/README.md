# OMBI — Ordered Minimum via Bitmap Indexing

The core algorithm implementation.

## Files

| File | Description |
|------|-------------|
| `ombi.h` | Header: data structures (`BEntry`, `ColdEntry`), bitmap array, hot bucket array, constants |
| `ombi.cc` | Implementation: `sssp()`, `extractFirstLive()`, `addToBucket()`, `scanBitmapFirstLive()` |
| `main.cc` | DIMACS driver: reads `.gr`/`.ss` files, runs SSSP from each source, prints timing + checksum |
| `ombi_opt.h/cc` | Variant with `bucket_width = 1 × minArcLen` |
| `ombi_opt2.h/cc` | Variant with `bucket_width = 2 × minArcLen` |

## Key Constants

```cpp
HOT_BUCKETS = 1 << 14   // 16,384 buckets
BMP_WORDS   = 256        // 16,384 / 64 = 256 bitmap words (2 KB)
MASK        = 16,383     // HOT_BUCKETS - 1
BW_MULT     = 4          // bucket_width = 4 × min_arc_weight
```

## Algorithm Flow

```
sssp(source):
  dist[source] = 0
  addToBucket(source, 0)
  while hot buckets or cold PQ not empty:
    v = extractFirstLive()       // bitmap scan → TZCNT → bucket
    for each edge (v, w):
      if dist[v] + weight < dist[w]:
        dist[w] = dist[v] + weight
        addToBucket(w, dist[w])  // set bitmap bit, push to bucket
```
