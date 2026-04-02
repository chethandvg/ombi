# 🗺️ What We Discovered — Explained From Scratch

> **Audience:** Anyone curious. No CS degree required.  
> **Reading time:** ~20 minutes  
> **TL;DR:** We found that a popular shortcut used by GPS apps and game engines has a hidden trap — and we can prove it mathematically.
>
> 🗺️ **Want the practical implications?** See [REAL_WORLD_IMPLICATIONS.md](REAL_WORLD_IMPLICATIONS.md) for what our theorems mean for GPS, routing engines, and navigation.

---

## Stage 1: The Problem GPS Apps Solve Every Day

### What is "Shortest Path"?

Imagine you're in a city and want to drive from **Home** to **Office**. There are many possible routes:

```
                    ┌─── Highway (12 min) ───┐
                    │                         │
   🏠 Home ────────┤                         ├──────── 🏢 Office
                    │                         │
                    └─ Side streets (20 min) ─┘
```

The **shortest path problem** asks: *What is the fastest route?*

This sounds simple with 2 routes. But a real city has **millions** of intersections and roads. Google Maps, Waze, game AI pathfinding, network routing — they all solve this problem **billions of times per day**.

### Dijkstra's Algorithm — The Gold Standard (1959)

A Dutch computer scientist named **Edsger Dijkstra** invented an algorithm in 1959 that finds the shortest path **perfectly**. It's been the foundation of route-finding for 65+ years.

**How it works (simplified):**

Think of it like pouring water from your starting point. Water flows along all roads simultaneously, and the first drop to reach any intersection tells you the shortest time to get there.

```
Step 1:  Start at Home (time = 0 min)
         ↓
Step 2:  Water reaches Gas Station (3 min) and Park (5 min)
         ↓
Step 3:  From Gas Station, water reaches Mall (3+4 = 7 min)
         ↓
Step 4:  From Park, water reaches Mall (5+1 = 6 min) ← SHORTER!
         ↓
Step 5:  Mall's shortest time = 6 min ✓
```

The key rule: **always process the closest unvisited place first**. This guarantees correctness.

### The Speed Problem

Dijkstra's algorithm needs a **priority queue** — a data structure that always gives you the closest unvisited place. Think of it as a "who's next?" list sorted by distance.

For small maps, this is fast. But for the entire USA road network (**24 million intersections, 58 million road segments**), even tiny inefficiencies add up.

| Priority Queue Type | Time per Operation | Total for USA |
|--------------------|--------------------|---------------|
| Simple sorted list | Slow (scan all) | ~Minutes |
| Binary heap | Medium (log n) | ~Seconds |
| **Bucket queue** | **Fast (nearly O(1))** | **~Milliseconds** |

The **bucket queue** is the speed champion. But it comes with a catch...


---

## Stage 2: Bucket Queues — Trading Precision for Speed

### The Analogy: Sorting Mail

Imagine you work at a post office. You have 1,000 letters to sort by zip code.

**Method A (Precise):** Read each zip code, put the letter in exact order. Slow but perfect.

**Method B (Buckets):** Set up 10 bins labeled "00000–09999", "10000–19999", etc. Toss each letter into the right bin. Then process bin by bin.

```
  ┌─────────┬─────────┬─────────┬─────────┬─────────┐
  │  Bin 0  │  Bin 1  │  Bin 2  │  Bin 3  │  Bin 4  │
  │ 0-9999  │ 10000-  │ 20000-  │ 30000-  │ 40000-  │
  │         │  19999  │  29999  │  39999  │  49999  │
  ├─────────┼─────────┼─────────┼─────────┼─────────┤
  │ 📬 📬 📬 │ 📬 📬    │ 📬      │ 📬 📬 📬 │ 📬 📬    │
  │ 📬 📬    │ 📬 📬 📬 │ 📬 📬    │ 📬      │         │
  └─────────┴─────────┴─────────┴─────────┴─────────┘
```

Method B is **much faster** — you barely look at each letter. But letters **within the same bin are not sorted**. If you need exact order, you'd have to sort within each bin too.

### Bucket Queue for Shortest Paths

A **bucket queue** does exactly this for distances:

```
  Bucket width (Δ) = 10 minutes

  ┌──────────┬──────────┬──────────┬──────────┬──────────┐
  │ Bucket 0 │ Bucket 1 │ Bucket 2 │ Bucket 3 │ Bucket 4 │
  │  0-9 min │ 10-19 min│ 20-29 min│ 30-39 min│ 40-49 min│
  ├──────────┼──────────┼──────────┼──────────┼──────────┤
  │ Home(0)  │ Mall(12) │ Park(25) │ Office   │          │
  │ Gas(3)   │ School   │ Zoo(22)  │  (35)    │          │
  │ Shop(7)  │  (15)    │          │          │          │
  └──────────┴──────────┴──────────┴──────────┴──────────┘
```

Instead of finding THE closest place (exact priority queue), we just process **the lowest non-empty bucket**. Everything in Bucket 0 is processed before Bucket 1, etc.

**The speed gain is enormous** — instead of maintaining a sorted structure, we just compute `bucket_number = distance ÷ bucket_width` and drop the item in. That's a single division!

### The Catch: Order Within a Bucket

Within Bucket 0, we have Home (0 min), Gas Station (3 min), and Shop (7 min). The correct order is Home → Gas → Shop. But the bucket queue doesn't sort them!

**How they get processed depends on the extraction rule:**

| Rule | Order | Description |
|------|-------|-------------|
| **FIFO** (First In, First Out) | Home → Gas → Shop | Like a queue at a store |
| **LIFO** (Last In, First Out) | Shop → Gas → Home | Like a stack of plates |
| Random | Any order | Chaos |

**LIFO** is the most common in practice because it's the fastest — a stack is simpler than a queue. You just push onto a pile and pop from the top.

### When Does This Go Wrong?

If the bucket width is **small enough** (≤ the smallest road weight), then any two places in the same bucket have distances so close that the order doesn't matter. This is the **Dinitz bound** (1978):

> 🛡️ **Dinitz Guarantee:** If `bucket_width ≤ smallest_edge_weight`, the algorithm is **always correct**, regardless of extraction order.

But what if we use **wider buckets** for more speed? Then places with very different distances end up in the same bucket, and LIFO might process them in the wrong order...

```
  Bucket width = 10

  ┌─────────────────────────┐
  │       Bucket 0          │
  │  ┌───┐ ┌───┐ ┌───┐     │    LIFO extracts Shop(7) first!
  │  │ H │ │ G │ │ S │ ←── │    But Home(0) should go first.
  │  │ 0 │ │ 3 │ │ 7 │     │    If Shop gets "settled" with a
  │  └───┘ └───┘ └───┘     │    wrong distance... ERROR!
  └─────────────────────────┘
```

---

## Stage 3: A Concrete Error — The Diamond Graph

### The Simplest Graph That Breaks

We designed the smallest possible graph that demonstrates the problem. We call it the **Diamond Graph** D(P, W):

```
         P = 4 min            W = 2 min
    🏠 ═══════════► (a) ═══════════► 🏢
   Home    fast       Airport         Office
    │      route                       ▲
    │                                  │
    │  1 min              P+W = 6 min  │
    └──────────► (b) ─────────────────►┘
       cheap      Gas       slow
       start    Station     route
```

**Two routes from Home to Office:**
- 🟢 **Fast route:** Home → Airport → Office = 4 + 2 = **6 min** ← CORRECT ANSWER
- 🔴 **Slow route:** Home → Gas Station → Office = 1 + 6 = **7 min**

The correct shortest path is **6 minutes**. Any algorithm worth its salt should find this.

### Let's Run It With Bucket Width = 4

Now let's trace what LIFO bucket queue does with `bucket_width = 4`:

```
  Which bucket does each place go into?
  bucket_number = distance ÷ bucket_width  (drop the remainder)

  Home:         0 ÷ 4 = Bucket 0
  Gas Station:  1 ÷ 4 = Bucket 0
  Airport:      4 ÷ 4 = Bucket 1
  Office (slow): 7 ÷ 4 = Bucket 1    ← via Gas Station
  Office (fast): 6 ÷ 4 = Bucket 1    ← via Airport
```

**Step-by-step execution:**

```
  STEP 1: Start at Home (distance = 0, Bucket 0)
  ┌────────────┬────────────┬────────────┐
  │  Bucket 0  │  Bucket 1  │  Bucket 2  │
  │  Home(0)   │            │            │
  └────────────┴────────────┴────────────┘
  Extract Home (only item). Discover neighbors:
    → Gas Station: dist = 0 + 1 = 1  → Bucket 0
    → Airport:     dist = 0 + 4 = 4  → Bucket 1

  STEP 2: Bucket 0 has Gas Station
  ┌────────────┬────────────┬────────────┐
  │  Bucket 0  │  Bucket 1  │  Bucket 2  │
  │  Gas(1)    │  Airport(4)│            │
  └────────────┴────────────┴────────────┘
  Extract Gas Station (dist = 1). Discover neighbors:
    → Office: dist = 1 + 6 = 7  → 7 ÷ 4 = Bucket 1
  
  Push Office(7) into Bucket 1.

  STEP 3: Bucket 0 is empty. Move to Bucket 1.
  ┌────────────┬────────────────────┬────────────┐
  │  Bucket 0  │     Bucket 1       │  Bucket 2  │
  │  (empty)   │  Airport(4)        │            │
  │            │  Office(7) ← TOP   │            │
  └────────────┴────────────────────┴────────────┘
  
  🚨 LIFO = take from TOP of the stack!
  
  Office(7) was pushed LAST, so it's on TOP.
  Extract Office with distance 7. Office is now SETTLED at 7.

  STEP 4: Process Airport(4) from Bucket 1.
  ┌────────────┬────────────┬────────────┐
  │  Bucket 0  │  Bucket 1  │  Bucket 2  │
  │  (empty)   │  Airport(4)│            │
  └────────────┴────────────┴────────────┘
  Extract Airport (dist = 4). Discover neighbors:
    → Office: dist = 4 + 2 = 6
    But Office is already SETTLED at 7. Too late!
```

### The Verdict

```
  ┌─────────────────────────────────────────────────┐
  │  RESULT WITH BUCKET WIDTH = 4:                  │
  │                                                 │
  │  Office distance = 7  ❌ WRONG!                 │
  │  Correct answer  = 6                            │
  │  Error           = +1 minute                    │
  │                                                 │
  │  Root cause: Airport(4) and Office(7) landed    │
  │  in the SAME bucket. LIFO processed Office      │
  │  first, locking in the wrong answer.            │
  └─────────────────────────────────────────────────┘
```

### What If We Use Bucket Width = 5?

Let's try a **wider** bucket:

```
  bucket_number = distance ÷ 5

  Home:         0 ÷ 5 = Bucket 0
  Gas Station:  1 ÷ 5 = Bucket 0
  Airport:      4 ÷ 5 = Bucket 0    ← now in Bucket 0!
  Office (slow): 7 ÷ 5 = Bucket 1
  Office (fast): 6 ÷ 5 = Bucket 1
```

**Trace:**
```
  Step 1: Extract Home(0) from Bucket 0
    → Gas(1) → Bucket 0,  Airport(4) → Bucket 0
  
  Step 2: Bucket 0 has [Gas(1), Airport(4)]. LIFO → extract Airport(4)
    → Office: 4+2 = 6 → Bucket 1. Push Office(6).
  
  Step 3: Bucket 0 has [Gas(1)]. Extract Gas(1).
    → Office: 1+6 = 7. But Office already has 6. No update (7 > 6).
  
  Step 4: Bucket 1 has [Office(6)]. Extract Office(6). SETTLED at 6. ✅
```

**Result with bucket width = 5: Office = 6 ✅ CORRECT!**

Wait... **wider bucket = 5 gives the RIGHT answer**, but **narrower bucket = 4 gave WRONG?**

That's... backwards! You'd expect wider buckets to be *less* accurate, not more!

### The Surprise Table

| Bucket Width | Office Distance | Correct? |
|:---:|:---:|:---:|
| 1 | 6 | ✅ Safe (Dinitz bound) |
| 2 | 6 | ✅ Safe (Dinitz bound) |
| 3 | 6 | ✅ Safe |
| **4** | **7** | **❌ ERROR** |
| **5** | **6** | **✅ Safe** |
| **6** | **6** | **✅ Safe** |
| **7** | **6** | **✅ Safe** |
| **8** | **7** | **❌ ERROR** |
| 9 | 7 | ❌ ERROR |
| 10 | 7 | ❌ ERROR |

Look at that pattern! Error at 4, then **safe at 5, 6, 7**, then error again at 8!

**This is the non-monotonicity we discovered.** The errors don't just start and keep going — they come and go in a wave pattern.

---

## Stage 4: Why It Happens — The Bucket Boundary Dance

### The Key Insight: It's All About Who Shares a Bucket

The error **only** happens when Airport and Office land in the **same bucket**. When they're in different buckets, Airport (being closer) is always in a lower bucket and gets processed first — no problem.

So the question becomes: **for which bucket widths do Airport (distance=4) and Office (distance=7) share a bucket?**

```
  Airport distance = P = 4
  Office distance  = P + W + 1 = 7    (the wrong distance, via Gas Station)
  
  They share a bucket when:  ⌊4 ÷ Δ⌋ = ⌊7 ÷ Δ⌋
  
  (⌊ ⌋ means "round down" — e.g., ⌊7 ÷ 4⌋ = ⌊1.75⌋ = 1)
```

Let's check every bucket width:

```
  Δ=1:  ⌊4/1⌋=4,  ⌊7/1⌋=7   → Different buckets (4≠7) → SAFE ✅
  Δ=2:  ⌊4/2⌋=2,  ⌊7/2⌋=3   → Different buckets (2≠3) → SAFE ✅
  Δ=3:  ⌊4/3⌋=1,  ⌊7/3⌋=2   → Different buckets (1≠2) → SAFE ✅
  Δ=4:  ⌊4/4⌋=1,  ⌊7/4⌋=1   → SAME BUCKET! (1=1)      → ERROR ❌
  Δ=5:  ⌊4/5⌋=0,  ⌊7/5⌋=1   → Different buckets (0≠1) → SAFE ✅
  Δ=6:  ⌊4/6⌋=0,  ⌊7/6⌋=1   → Different buckets (0≠1) → SAFE ✅
  Δ=7:  ⌊4/7⌋=0,  ⌊7/7⌋=1   → Different buckets (0≠1) → SAFE ✅
  Δ=8:  ⌊4/8⌋=0,  ⌊7/8⌋=0   → SAME BUCKET! (0=0)      → ERROR ❌
```

### Visualizing the Bucket Boundaries

Think of bucket boundaries as **walls** placed at regular intervals on a number line. The question is: do the walls separate Airport (4) from Office (7)?

```
  Δ=3: Walls at 0, 3, 6, 9...
  
  0         3         6         9
  |─────────|─────────|─────────|─────────
            ·    A    ·  O      ·
            ·    ↑    ·  ↑      ·
            · Airport · Office  ·
            ·   (4)   ·  (7)    ·
                      ▲
                  WALL between them → SAFE ✅
```

```
  Δ=4: Walls at 0, 4, 8, 12...
  
  0              4              8
  |──────────────|──────────────|──────────
                 A    ·    O
                 ↑    ·    ↑
              Airport · Office
                (4)   ·  (7)
                      
              NO wall between them → ERROR ❌
              (both in the 4-to-7 region of the same bucket)
```

```
  Δ=5: Walls at 0, 5, 10...
  
  0                   5                   10
  |───────────────────|───────────────────|──
            A         ·    O
            ↑         ·    ↑
         Airport      · Office
           (4)        ·  (7)
                      ▲
                  WALL between them → SAFE ✅
```

```
  Δ=8: Walls at 0, 8, 16...
  
  0                                       8
  |───────────────────────────────────────|──
            A              O
            ↑              ↑
         Airport        Office
           (4)           (7)
  
              NO wall between them → ERROR ❌
              (both in the giant 0-to-7 region)
```

### The Pattern: Walls Come and Go

As you increase the bucket width, the walls **move**. Sometimes a wall lands between Airport(4) and Office(7), sometimes it doesn't. It's like a **picket fence** that you're stretching wider and wider:

```
  Δ=1: |·|·|·|·|A|·|·|O|·|     Many walls → always separated
  Δ=2: |· ·|· ·|A ·|· O|· ·|   Still separated
  Δ=3: |· · ·|· A ·|· O · |    Still separated  
  Δ=4: |· · · ·|A · · O|· · · ·|  COLLISION! Same bucket!
  Δ=5: |· · · · A|· · O · ·|   Separated again!
  Δ=6: |· · · · A ·|· O · · · ·| Separated!
  Δ=7: |· · · · A · ·|O · · · · · ·| Separated!
  Δ=8: |· · · · A · · O|· · · · · · · ·| COLLISION again!
```

**This is the non-monotonicity!** The wall sometimes falls between 4 and 7, sometimes doesn't, depending on the exact bucket width. It's not a simple "wider = worse" relationship — it's a **number theory** pattern.

### The Formula We Discovered

After analyzing this pattern, we found the exact rule:

> 📐 **Error Formula:**  
> Error happens when `bucket_width > W+1` **AND** `P mod bucket_width < bucket_width - W - 1`
>
> Where `P mod Δ` is the remainder when you divide P by Δ.

For our D(4, 2) example:
- `W + 1 = 3`, so bucket widths ≤ 3 are always safe
- For Δ = 4: `4 mod 4 = 0`, threshold = `4 - 2 - 1 = 1`, is `0 < 1`? **YES → ERROR** ❌
- For Δ = 5: `4 mod 5 = 4`, threshold = `5 - 2 - 1 = 2`, is `4 < 2`? **NO → SAFE** ✅
- For Δ = 8: `4 mod 8 = 4`, threshold = `8 - 2 - 1 = 5`, is `4 < 5`? **YES → ERROR** ❌

It works perfectly. The remainder `P mod Δ` tells you how close Airport is to a bucket boundary. When it's close (small remainder), Office sneaks into the same bucket. When it's far (large remainder), a wall separates them.


---

## Stage 5: Why This Matters in the Real World

### 🗺️ Real-World Application 1: GPS Navigation

Google Maps, Waze, Apple Maps — they all need to compute shortest paths on massive road networks. Many use bucket-queue-based algorithms (or their parallel cousin, **Δ-stepping**) because they're fast.

**The conventional wisdom was:**

> "Use a small bucket width for accuracy, or a large one for speed. The tradeoff is simple — smaller = more accurate."

**What we proved:**

> "That's WRONG. A bucket width of 100 might give errors, 101–110 might be perfect, and 111 might have errors again. The relationship between bucket width and correctness is chaotic."

**Practical impact:** If an engineer tunes their bucket width by testing a few values and seeing errors decrease, they might pick a value that *happens* to be in a safe gap — but a slightly different map update could shift the distances and make it unsafe again.

### 🎮 Real-World Application 2: Video Game Pathfinding

Games like StarCraft, Age of Empires, Civilization, and any RTS/strategy game use pathfinding constantly. Hundreds of units need paths every frame. Bucket queues are popular because they're fast.

```
  ┌───────────────────────────────────────┐
  │  🏰 Castle                            │
  │    ↓                                  │
  │  ⚔️ Knight needs to reach enemy base  │
  │    ↓                                  │
  │  Path options:                        │
  │    Route A: Through forest (slow)     │
  │    Route B: Around mountain (fast)    │
  │    Route C: Through swamp (medium)    │
  │                                       │
  │  With wrong bucket width, knight      │
  │  might take the FOREST route even     │
  │  though MOUNTAIN route is faster!     │
  └───────────────────────────────────────┘
```

In games, a wrong path isn't just inefficient — it can make units walk into enemy fire, look stupid, or get stuck. Game developers often use wider buckets for speed and accept "close enough" paths. Our result shows the error behavior is much more unpredictable than they assumed.

### 🌐 Real-World Application 3: Network Routing

Internet routers use shortest-path algorithms (like OSPF — Open Shortest Path First) to decide where to send data packets. While they typically use exact Dijkstra, some high-performance routers use approximate methods.

**If a router uses bucket queues with a too-wide bucket width, packets could take suboptimal routes** — adding milliseconds of latency. For high-frequency trading, online gaming, or video calls, those milliseconds matter.

### 📊 How Bad Is It on Real Maps?

We tested on actual US road networks (DIMACS benchmark):

```
  ┌────────────────────────────────────────────────────────────┐
  │              Dinitz Bound vs. Actual Safe Boundary         │
  │                                                            │
  │  Graph         Dinitz says    Actually safe    Ratio       │
  │  ─────────     ──────────    ────────────     ─────       │
  │  Bay Area         ≤ 2           ≤ 48          24× better! │
  │  Colorado         ≤ 2           ≤ 52          26× better! │
  │  Florida          ≤ 1           ≤ 54          54× better! │
  │  Northwest        ≤ 2           ≤ 26          13× better! │
  │  Northeast        ≤ 2           ≤ 8            4× better! │
  │  Full USA         ≤ 1           ≤ 8            8× better! │
  │                                                            │
  │  "Dinitz says ≤ 2" means: the 1978 theorem guarantees     │
  │  correctness only for bucket width 1 or 2.                │
  │                                                            │
  │  "Actually safe ≤ 48" means: we tested every bucket width │
  │  and found it's correct up to 48!                          │
  └────────────────────────────────────────────────────────────┘
```

**The Dinitz bound is extremely conservative** — you could use buckets 24× wider and still get perfect answers! That means 24× fewer buckets, which means significantly faster computation.

But here's the catch our theorem reveals: **you can't just binary-search for that boundary**. You have to test *every single* bucket width, because the errors come and go unpredictably.


---

## Stage 6: The Binary Search Trap

### What Is Binary Search?

Binary search is one of the most fundamental tricks in computer science. It's how you find a word in a dictionary:

```
  Looking for "Monkey" in a 1000-page dictionary:
  
  Step 1: Open to page 500. See "Octopus". Monkey < Octopus → go LEFT
  Step 2: Open to page 250. See "Giraffe". Monkey > Giraffe → go RIGHT  
  Step 3: Open to page 375. See "Lion".    Monkey > Lion    → go RIGHT
  Step 4: Open to page 437. See "Mango".   Monkey > Mango   → go RIGHT
  Step 5: Open to page 468. See "Moon".    Monkey < Moon    → go LEFT
  Step 6: Open to page 452. See "Monkey"!  FOUND in 6 steps!
  
  Instead of checking all 1000 pages, we only needed 6. (log₂ 1000 ≈ 10)
```

Binary search works when things are **monotonic** — sorted in order. Words in a dictionary are sorted alphabetically. If page 500 has "Octopus" and you want "Monkey", you *know* Monkey must be on pages 1–499. You can safely ignore pages 501–1000.

### Why People Assumed Binary Search Would Work Here

The natural assumption was:

> "If bucket_width = 50 gives errors, then bucket_width = 100 *definitely* gives errors too (it's even wider!). So I can binary search for the boundary between 'safe' and 'error'."

```
  The ASSUMED error pattern:
  
  Bucket width:  1  2  3  4  5  6  7  8  9  10  11  12 ...
  Error?:        ✅ ✅ ✅ ✅ ✅ ❌ ❌ ❌ ❌ ❌  ❌  ❌ ...
                 safe safe safe safe safe err err err err err
                                    ▲
                              Clean boundary!
                         Binary search finds this.
```

### What Actually Happens

```
  The ACTUAL error pattern (D(100, 10)):
  
  Bucket width:  2  ...  11  12  13  14  15  16  17  18  ...  111  112 ...
  Error?:        ✅      ✅  ✅  ✅  ❌  ✅  ❌  ✅  ✅       ✅   ❌  ...
                 safe    safe safe safe ERR safe ERR safe      safe ERR
                                   ▲        ▲
                              Errors pop up in the middle of safe zones!
```

There's no clean boundary. It's like a dictionary where the words are **NOT** in alphabetical order — "Monkey" might be on page 700, between "Zebra" and "Apple". Binary search would never find it.

### A Concrete Disaster

We ran binary search on our diamond graph D(100, 10), searching for the largest safe bucket width in [2, 200]:

```
  ┌──────────────────────────────────────────────────────────┐
  │  BINARY SEARCH TRACE:                                    │
  │                                                          │
  │  Test Δ=101 → SAFE    → "everything ≤ 101 must be safe" │
  │  Test Δ=151 → ERROR   → search [101, 150]               │
  │  Test Δ=126 → ERROR   → search [101, 125]               │
  │  Test Δ=113 → ERROR   → search [101, 112]               │
  │  Test Δ=107 → SAFE    → search [107, 112]               │
  │  Test Δ=110 → SAFE    → search [110, 112]               │
  │  Test Δ=111 → SAFE    → search [111, 112]               │
  │  Test Δ=112 → ERROR   → search [111, 111]               │
  │                                                          │
  │  Binary search answer: B_safe = 111                      │
  │  Actual answer:        B_safe = 13                       │
  │                                                          │
  │  ❌ OFF BY 98!                                           │
  │                                                          │
  │  Binary search says "safe up to 111" but there are       │
  │  errors at Δ = 14, 16, 19, 20, 23, 24, 25, ...          │
  │  It missed ALL of them because it never checked!         │
  └──────────────────────────────────────────────────────────┘
```

Binary search tested Δ=101 and saw "SAFE". It concluded everything below 101 must also be safe. **Wrong!** There are dozens of error-producing bucket widths below 101 — it just never looked at them.

### The Fundamental Lesson

```
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │  🚫 You CANNOT use binary search to find the safe       │
  │     boundary for bucket-queue Dijkstra.                  │
  │                                                          │
  │  ✅ You MUST test every single bucket width.             │
  │                                                          │
  │  This is because the error function is NON-MONOTONIC:    │
  │  errors appear, disappear, and reappear as the bucket    │
  │  width increases.                                        │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
```

This has a real cost: if your graph has edge weights up to 10,000, you might need to test all bucket widths from 1 to 10,000 instead of doing ~14 binary search steps. That's a 700× slowdown in finding the safe boundary.

---

## Stage 7: The Big Picture — What We Contributed to Science

### Before Our Work

```
  What was known (1978–2025):
  
  ┌─────────────────────────────────────────────────┐
  │  "Bucket width ≤ smallest edge weight → safe"   │
  │                                                  │
  │  That's it. That's the entire theory.            │
  │  One line. Published in 1978 by Dinitz.          │
  │  Nothing else was known for 47 years.            │
  └─────────────────────────────────────────────────┘
```

### After Our Work

```
  What is now known (2025):
  
  ┌─────────────────────────────────────────────────────────┐
  │  1. The error function is NON-MONOTONIC (Theorem 1)     │
  │     → Errors come and go as bucket width increases      │
  │                                                         │
  │  2. Gap size = W+1, exact (Theorem 2)                   │
  │     → We know exactly how big the safe gaps are         │
  │                                                         │
  │  3. Gaps can be ARBITRARILY LARGE (Theorem 3)           │
  │     → Even on tiny 4-vertex graphs!                     │
  │                                                         │
  │  4. Multiple gaps exist in composed graphs (Theorem 4)  │
  │     → Real-world graphs have complex error landscapes   │
  │                                                         │
  │  5. Complete formula for diamond graphs (Theorem 5)     │
  │     → First exact characterization ever                 │
  │                                                         │
  │  6. Binary search is UNSOUND (Corollary)                │
  │     → A common optimization technique doesn't work here │
  │                                                         │
  │  7. Floating-point changes the boundary (Observation)   │
  │     → Implementation details affect correctness!        │
  │                                                         │
  │  8. Real maps have 4×–54× gap over Dinitz (Experiments) │
  │     → Huge practical speedup potential                  │
  └─────────────────────────────────────────────────────────┘
```

### An Everyday Analogy

Imagine you're adjusting the **sensitivity** of a smoke detector:

- **Low sensitivity (small bucket):** Detects everything perfectly but goes off when you make toast. Annoying but safe.
- **High sensitivity (large bucket):** Fast and quiet but might miss a real fire.

The **old understanding** was: *"As you turn up the sensitivity, it gets less reliable in a smooth, predictable way."*

**What we discovered:** *"Actually, sensitivity 7 misses fires, sensitivity 8 catches them all, sensitivity 9 misses fires again, and sensitivity 10 catches them. It's like the detector has a mind of its own."*

This means you can't just test a few settings and interpolate. You have to test **every single setting** to know which ones are safe.

### Why This Is Publishable

| Criterion | Our Result |
|-----------|-----------|
| **Novel?** | Yes — first analysis of LIFO extraction order in 47 years |
| **Surprising?** | Yes — contradicts the "wider = worse" intuition |
| **Minimal?** | Yes — 4 vertices, 4 edges. Can't get simpler. |
| **Complete?** | Yes — exact closed-form formula, not just examples |
| **Practical?** | Yes — affects GPS, games, network routing |
| **Verified?** | Yes — 377,310 test cases, 0 mismatches |

---

## 🎓 Glossary

| Term | Meaning |
|------|---------|
| **Dijkstra's Algorithm** | The standard algorithm for finding shortest paths in a graph (1959) |
| **Bucket Queue** | A fast priority queue that groups items into "buckets" by distance range |
| **Bucket Width (Δ)** | How wide each bucket is — items within Δ distance of each other share a bucket |
| **LIFO** | Last In, First Out — like a stack of plates, you take from the top |
| **FIFO** | First In, First Out — like a queue at a store, first person served first |
| **Dinitz Bound** | The 1978 theorem: bucket width ≤ min edge weight → always correct |
| **B_safe** | The largest bucket width that still gives correct answers for a specific graph |
| **Non-monotonic** | Not always increasing or always decreasing — goes up AND down |
| **Diamond Graph D(P,W)** | Our 4-vertex test graph with two routes to the destination |
| **P mod Δ** | Remainder when dividing P by Δ (e.g., 7 mod 3 = 1, because 7 = 2×3 + 1) |
| **Binary Search** | An algorithm that finds a value by repeatedly halving the search range |
| **Δ-stepping** | A parallel version of bucket-queue Dijkstra used in high-performance computing |

---

> 📄 **Full formal proofs:** See `PROOF_NONMONOTONICITY.md`  
> 📊 **Paper outline:** See `PAPER_OUTLINE.md`  
> 💻 **Verification code:** Run `dotnet run -c Release -- proof` in the `csharp/` directory

