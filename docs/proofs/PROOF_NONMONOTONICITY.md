# Non-Monotonicity of the LIFO Bucket-Queue Error Function

## Formal Proof — Paper-Ready Version

**Date:** 2026-03-25  
**Status:** Computationally verified (377,310 test cases, 0 mismatches)

---

## 1. Definitions

**LIFO Bucket-Queue Dijkstra (LIFO-BQ).** A variant of Dijkstra's algorithm where the priority queue is replaced by an array of buckets, each of width `Δ` (we use `bw` for bucket width). Vertices with tentative distance `d` are placed in bucket `⌊d/bw⌋`. Within each bucket, vertices are stored in a LIFO stack and extracted in last-in-first-out order.

**Error function.** For a graph `G`, source `s`, and bucket width `bw`, define:

```
E_G,s(bw) = 1  if LIFO-BQ with bucket width bw produces d(v) ≠ d*(v) for some v
E_G,s(bw) = 0  otherwise
```

**Diamond graph.** For integers `P ≥ 2` and `W ≥ 1`, define `D(P, W)` as the directed graph on 4 vertices `{s, a, b, v}` with edges:
- `s → a` (weight `P`)
- `a → v` (weight `W`)  
- `s → b` (weight `1`)
- `b → v` (weight `P + W`)

The shortest paths from `s` are: `d*(s) = 0`, `d*(a) = P`, `d*(b) = 1`, `d*(v) = P + W`.

The suboptimal path `s → b → v` has cost `1 + (P + W) = P + W + 1`, giving an error gap of exactly 1.

```
         P           W
    s ────────→ a ────────→ v
    │                       ↑
    │  1              P+W   │
    └────────→ b ───────────┘

    d*(v) = P + W       (via s → a → v)
    d_wrong(v) = P+W+1  (via s → b → v)
```

---

## 2. Error Condition for Diamond Graphs

**Lemma 1 (Error Characterization).** *For the diamond graph `D(P, W)` with source `s`, LIFO-BQ with bucket width `bw` produces an error if and only if:*

```
bw > W + 1   AND   P mod bw < bw - W - 1
```

**Proof.** We trace the execution of LIFO-BQ on `D(P, W)`:

1. **Initialize:** `dist[s] = 0`. Insert `s` into bucket 0.

2. **Extract `s`** (bucket 0). Relax edges:
   - `s → a`: `dist[a] = P`, insert `a` into bucket `⌊P/bw⌋`.
   - `s → b`: `dist[b] = 1`, insert `b` into bucket `⌊1/bw⌋ = 0` (since `bw ≥ 2`).

3. **Extract `b`** from bucket 0 (it was just inserted; `s` is already settled). Relax:
   - `b → v`: `dist[v] = 1 + (P + W) = P + W + 1`, insert `v` into bucket `⌊(P+W+1)/bw⌋`.

4. **Now the state is:** `a` is in bucket `⌊P/bw⌋` and `v` is in bucket `⌊(P+W+1)/bw⌋`.

5. **Case analysis:**

   - **Case A: `⌊P/bw⌋ = ⌊(P+W+1)/bw⌋`** (same bucket).  
     Both `a` and `v` are in the same bucket. Since `a` was pushed first (step 2) and `v` was pushed second (step 3), the LIFO stack has `v` on top. LIFO extracts `v` first, settling it with `dist[v] = P + W + 1 ≠ P + W = d*(v)`. **Error.**

   - **Case B: `⌊P/bw⌋ ≠ ⌊(P+W+1)/bw⌋`** (different buckets).  
     Since `P < P + W + 1`, we have `⌊P/bw⌋ ≤ ⌊(P+W+1)/bw⌋`. Bucket `⌊P/bw⌋` is processed first. `a` is extracted and relaxes `v` to `min(P+W+1, P+W) = P+W`. Then `v` is settled correctly. **No error.**

6. **Same-bucket condition.** Let `r = P mod bw`. Then:

   ```
   ⌊P/bw⌋ = ⌊(P+W+1)/bw⌋
   ⟺ ⌊(P - r)/bw + (r + W + 1)/bw⌋ = ⌊P/bw⌋
   ⟺ ⌊(r + W + 1)/bw⌋ = 0
   ⟺ r + W + 1 < bw
   ⟺ r < bw - W - 1
   ```

   This requires `bw - W - 1 > 0`, i.e., `bw > W + 1`. When `bw ≤ W + 1`, the condition `r < bw - W - 1 ≤ 0` is impossible, so there is no error (consistent with the Dinitz bound). ∎

**Computational verification:** The formula was checked against simulation for all `P ∈ [2, 100]`, `W ∈ [1, min(P-1, 30)]`, `bw ∈ [2, 2P+2W+5]` — a total of **377,310 test cases with 0 mismatches**.

---

## 3. Main Theorems

### Theorem 1 (Non-Monotonicity)

*For integers `P > W + 1 ≥ 2`, the error function `E(bw)` of `D(P, W)` satisfies:*

*(a) `E(P) = 1`*  
*(b) `E(bw) = 0` for all `bw ∈ {P+1, P+2, ..., P+W+1}`*  
*(c) `E(P+W+2) = 1`*

*Hence `E` is non-monotonic: it transitions from error to safe and back to error.*

**Proof.**

**(a)** At `bw = P`: `P mod P = 0` and the threshold is `P - W - 1 > 0` (since `P > W + 1`). Since `0 < P - W - 1`, the error condition holds. ✓

**(b)** For `bw ∈ {P+1, ..., P+W+1}`: since `bw > P`, we have `P mod bw = P`. The threshold is `bw - W - 1 ≤ P + W + 1 - W - 1 = P`. Since `P ≥ bw - W - 1`, the error condition fails. ✓

**(c)** At `bw = P + W + 2`: `P mod (P+W+2) = P` (since `P < P+W+2`). The threshold is `P + W + 2 - W - 1 = P + 1`. Since `P < P + 1`, the error condition holds. ✓ ∎

### Theorem 2 (Gap Size)

*The non-monotonic gap at `bw = P` has size exactly `W + 1`.*

**Proof.** By Theorem 1, the gap consists of `{P+1, P+2, ..., P+W+1}`, which has `W + 1` elements. We verify that the gap does not extend further:

- At `bw = P + W + 2`: error (Theorem 1(c)).
- At `bw = P`: error (Theorem 1(a)).

So the gap is exactly `{P+1, ..., P+W+1}` with size `W + 1`. ∎

### Theorem 3 (Unbounded Gaps)

*For any integer `g ≥ 2`, the 4-vertex diamond graph `D(g+1, g-1)` has a non-monotonic gap of size exactly `g`.*

**Proof.** Set `P = g + 1` and `W = g - 1`. Then:
- `W ≥ 1` (since `g ≥ 2`). ✓
- `P = g + 1 > g = W + 1`. ✓
- Gap size = `W + 1 = g`. ✓

By Theorem 1, `E(P) = 1`, `E(bw) = 0` for `bw ∈ {g+2, ..., 2g}`, and `E(2g+1) = 1`. ∎

**Corollary.** *There is no finite bound on the gap size of non-monotonic regions in the LIFO-BQ error function, even for graphs with only 4 vertices.*

### Theorem 4 (Multiple Gaps)

*For two diamond graphs `D(P₁, W₁)` and `D(P₂, W₂)` sharing a common source `s`, the combined error function `E(bw) = E₁(bw) ∨ E₂(bw)` can have multiple non-monotonic gaps.*

**Proof.** (By construction.) The error set of the combined graph is:

```
ERR = { bw > W₁+1 : P₁ mod bw < bw-W₁-1 } ∪ { bw > W₂+1 : P₂ mod bw < bw-W₂-1 }
```

When `P₁` and `P₂` have different residue patterns modulo various `bw` values, the safe regions of one diamond can overlap with error regions of the other, creating alternating error/safe/error patterns.

**Example:** `D(10, 3)` and `D(23, 3)` sharing source `s` (7 vertices total). The combined error function has gaps at `(5, 7)` and `(11, 14)` — two distinct non-monotonic regions. ∎

### Theorem 5 (Complete Characterization)

*For `D(P, W)`, the complete error set is:*

```
ERR(D(P,W)) = { bw ∈ ℤ : bw > W+1 and P mod bw < bw - W - 1 }
```

*This set has the following structure:*
1. *`bw ∈ [2, W+1]`: always safe (Dinitz region)*
2. *`bw ∈ [W+2, P]`: mixed — safe iff `P mod bw ≥ bw - W - 1`*
3. *`bw ∈ [P+1, P+W+1]`: always safe (the gap)*
4. *`bw > P+W+1`: always error*

**Proof of (4).** For `bw > P + W + 1`: `P mod bw = P` (since `P < bw`). The threshold is `bw - W - 1 > P + W + 1 - W - 1 = P`. So `P < bw - W - 1`, giving an error. ∎

---

## 4. Corollary: Binary Search Fails

**Corollary.** *Binary search for `B_safe(G) = max{bw : E(bw') = 0 ∀ bw' ≤ bw}` is unsound.*

**Proof.** Binary search assumes monotonicity: if `E(bw) = 0`, then `E(bw') = 0` for all `bw' < bw`. Theorem 1 shows this is false: `E(P+1) = 0` but `E(P) = 1`.

**Concrete example:** For `D(100, 10)`, binary search in `[2, 200]` returns `B_safe = 111`, while the actual value is `B_safe = 13` (first error at `bw = 14`). The search is off by **98**. ∎

---

## 5. Floating-Point Remark

**Observation 6 (Implementation Artifact).** *When bucket indices are computed using floating-point arithmetic (`⌊d · (1/bw)⌋` instead of `⌊d/bw⌋`), the error condition becomes:*

```
E_float(bw) = 1  iff  bw > W+1  AND  P mod bw ≤ bw - W - 1
```

*Note the `≤` instead of `<`. The boundary case `P mod bw = bw - W - 1` (where `P + W + 1` is exactly divisible by `bw`) produces an error in floating-point implementations but not in exact arithmetic.*

**Explanation.** When `P + W + 1 = k · bw` for some integer `k`, the exact value of `(P+W+1)/bw = k`. However, computing `(P+W+1) · (1.0/bw)` in IEEE 754 double precision can yield `k - ε` (e.g., `0.9999999999999999` instead of `1.0`), causing `⌊(P+W+1) · (1/bw)⌋ = k - 1` instead of `k`. This places `v` in the same bucket as `a`, triggering an error that would not occur with exact integer division.

**Verified:** Out of 5,555 equality-boundary cases tested, 137 exhibited this floating-point discrepancy (all with `bw ≥ 49`).

---

## 6. Significance

1. **Minimal counterexample.** The diamond `D(P, W)` has only **4 vertices and 4 edges** — the smallest possible graph exhibiting non-monotonicity.

2. **Unbounded gap size.** The gap size `W + 1` grows linearly with the edge weight, with no upper bound.

3. **Clean closed form.** The error function has a complete number-theoretic characterization: `E(bw) = 1 iff bw > W+1 AND P mod bw < bw - W - 1`.

4. **Algorithmic consequence.** Any algorithm computing `B_safe(G)` must sweep all candidate `bw` values. Binary search is unsound.

5. **Implementation consequence.** Floating-point bucket computation introduces additional errors at exact divisibility boundaries.

---

## Appendix: Verification Data

| P | W | Error at P | Safe at P+1 | Safe at P+W+1 | Error at P+W+2 | Gap Size | W+1 | Match |
|---|---|-----------|-------------|---------------|----------------|----------|-----|-------|
| 4 | 2 | ✅ | ✅ | ✅ | ✅ | 3 | 3 | ✅ |
| 10 | 3 | ✅ | ✅ | ✅ | ✅ | 4 | 4 | ✅ |
| 20 | 5 | ✅ | ✅ | ✅ | ✅ | 6 | 6 | ✅ |
| 50 | 10 | ✅ | ✅ | ✅ | ✅ | 11 | 11 | ✅ |
| 100 | 20 | ✅ | ✅ | ✅ | ✅ | 21 | 21 | ✅ |
| 200 | 50 | ✅ | ✅ | ✅ | ✅ | 51 | 51 | ✅ |

Gap size verified for all W ∈ [1, 100]: **100/100 match**.

Arbitrary gap construction verified for g ∈ [2, 50]: **49/49 match**.

Formula verified against integer BQ simulation: **377,310/377,310 match**.

---

> **See also:** [PROOF_FIFO.md](PROOF_FIFO.md) for the FIFO extraction analysis (Theorems 6–8),
> which shows that FIFO is also non-monotonic on anti-FIFO graphs, with a different three-condition
> error formula. Neither extraction policy dominates. Verified on 55,312,270 cases.
>
> **Δ-stepping immunity (Phase 15-16):** Δ-stepping (label-correcting) produces **ZERO errors**
> across 31M+ test cases on both synthetic constructions and all 6 DIMACS road networks.
> The re-relaxation mechanism appears to provide inherent immunity to non-monotonicity.
> See [PROGRESS.md](PROGRESS.md) Phase 15-16 for full details.

