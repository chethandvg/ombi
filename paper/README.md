# Paper Materials

Working title: **"The Error Function of Bucket-Queue Dijkstra is Non-Monotonic"**

Target venues: **ALENEX** (primary) / **SEA** (secondary) / **JEA** (backup)

## Contents

| File | Description |
|------|-------------|
| `PAPER_OUTLINE.md` | Detailed paper outline with section structure |
| `FIGURES.md` | Figure specifications and descriptions |
| `generate_plots.py` | Python script to generate all paper figures |
| `figures.ipynb` | Jupyter notebook for interactive figure exploration |

## Figure Generation

```bash
pip install matplotlib numpy pandas
python generate_plots.py
```

Reads CSV data from `../docs/data/` and `../benchmarks/results/`.
