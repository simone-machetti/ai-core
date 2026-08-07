# Unified-Core — slide content

---

## Unified-Core

Trading Multipliers for Squarers in a Multi-Format Matrix Engine

A hardware-sharing study on an N×N matrix multiplication grid — ASAP7, 7 nm

Simone Machetti

---

## Matrix multiplication: one kernel, two industries

$$C_{m,n} = \sum_{k} A_{m,k} \cdot B_{k,n}$$

- A grid of independent multiply–accumulate chains — 2·M·K·N operations, fully parallel, fully regular
- **AI** — it *is* the algorithm: linear projections, feed-forward layers, attention, convolution lowered to GEMM. Operands are aggressively quantized: 4-, 8-, 16-bit integers, and block floating point where dynamic range must be preserved
- **Wireless** — MIMO detection, beamforming and precoding, channel estimation. The same product, but **complex-valued**, and less tolerant of quantization error
- One engine for both ⇒ integer **and** complex arithmetic, across several precisions

---

## Optimizing the kernel: can we share hardware?

- Matrix multiplication dominates these workloads, so **any per-operation saving multiplies across the whole system**
- In our reference grid, the processing elements are **~96 % of both area and power** — everything else is noise. The compute unit is the only thing worth attacking
- A spatial array replicates that unit **N² times**. So:

> Hardware moved out of the compute unit into a shared position is paid **O(N)** times instead of **O(N²)**

- If part of the computation depends on **one operand only**, it can be hoisted out of the PE and amortized across a whole row or column
- **The question:** can matrix multiplication be restructured this way — and does the shared hardware cost less than what it removes?

---

## Reference design — an N×N grid of processing elements

- **N² processing elements**, one matrix product per PE
- Operand **A** enters from the left, broadcast along each **row**
- Operand **B** enters from the top, broadcast down each **column**
- PE[r][c] computes A[r] · B[c] — the outer product of a row of A-tiles with a column of B-tiles
- Each PE holds its own accumulator and output register
- Mode is **grid-wide**; row/column enables scale the active region; one result per PE per cycle

---

## From a large matrix product to the grid

**1 · Tile** — the large M×K×N product is split into tiles sized to what one PE evaluates in one cycle

**2 · Pack** — a tile's elements are placed into two fixed-width operand words: **256-bit A** and **256-bit B**, at fixed byte/nibble positions

**3 · Feed** — A words enter per row, B words per column; each PE receives one A tile and one B tile and produces its result

**4 · Accumulate** — a large K dimension is streamed as successive tiles into each PE's accumulator

---

## Supported formats — the constraint on any optimization

| Family | Used by | Note |
|---|---|---|
| **Integer** | AI | mixed precisions, mixed widths on A and B |
| **Complex integer** | Wireless | four real products per complex product |
| **Block floating point (BFP)** | AI | one exponent shared per block — floating-point dynamic range at integer cost |
| **Complex BFP** | Both | the two combined |

- These expand into **11 operating modes**, all reduced to a single narrow dot-product primitive
- **Every optimization must support all of them** — this is the bar the proposal is measured against

---

## Replacing the multiplier with a squarer

$$a \cdot b = \tfrac{1}{2}\left[(a+b)^2 - a^2 - b^2\right]$$

| Term   | Depends on  | Where it lives                                        | Instances |
| ------ | ----------- | ----------------------------------------------------- | --------- |
| (a+b)² | A **and** B | inside the PE — a **squarer** replaces the multiplier | **N²**    |
| a² (α) | **A only**  | hoisted out — **shared by the whole row**             | **N**     |
| b² (β) | **B only**  | hoisted out — **shared by the whole column**          | **N**     |

An N×N grid needs **N² squarers** but only **N α + N β** generators

The saving scales as **N²** — the added cost scales as **N**

(unsigned operands add a small per-mode constant, held in one shared table)

---

## The square grid

- Same N×N array, same broadcast structure — **PEs now square instead of multiply**
- **N α generators**, one per row, each fed by that row's A
- **N β generators**, one per column, each fed by that column's B
- Each PE combines its own square with the row's α, the column's β and the shared constant
- **Externally identical** to the reference: same interface, same formats, same latency
- Results are **bit-exact** to the reference — verified across all 11 modes and all four variants

---

## The BFP challenge — α and β have no scale of their own

- In the integer design the three terms travel **independently** and meet at the end: α reduced per row, β reduced per column, both merged with the square in the **accumulator**
- In BFP every value carries an exponent, and a block's scale is E = e_A + e_B — it depends on **both** operands
- But α is generated **per row** and sees only A; β is generated **per column** and sees only B

> Neither generator knows the scale at which its own correction must be injected

- So the integer structure breaks: α and β **cannot** be reduced in isolation and merged at the accumulator
- **Our solution — combine at the DP8 level, before any alignment:** {(a+b)², −α, −β, C} are folded **per block, at that block's own scale E**, by a single compressor
- Above that point the datapath is the **baseline BFP tree, unchanged** — and the generators lose their reduction trees entirely, shrinking the shared α/β hardware by **~38 %**

---

## Experimental setup

**Tools — fully open source**

| Step | Tool |
|---|---|
| Simulation | Verilator |
| Synthesis | Yosys |
| Place & route | OpenROAD |
| Timing & power analysis | OpenSTA |

**Technology**

- ASAP7, open-source **7 nm** predictive PDK

**Stimulus (for power)**

- Uniformly distributed random operands
- Full pipeline throughput — **fresh A and B every clock cycle**
- All rows and columns active, all 11 modes exercised
- Switching activity captured from gate-level simulation and annotated onto the netlist

**Four variants compared**

Baseline · Square · Baseline-BFP · Square-BFP

each square measured against **its own** baseline

---

## Area at the dot-product level

- Scope: the array of dot-product cores inside one PE — the arithmetic core, nothing else
- **The squarer is ~38 % smaller than the multiplier**
- **BFP costs nothing here** — the BFP variants reuse the integer core unchanged. The entire BFP overhead is downstream, in the reduction and accumulation stages

| Variant | Normalized area | vs own baseline |
|---|---|---|
| Baseline | 1.000 | — |
| Square | 0.619 | **−38.1 %** |
| Baseline-BFP | 1.010 | — |
| Square-BFP | 0.619 | **−38.8 %** |

---

## Area at the PE level — where the saving goes

- Scope: the complete processing element
- The −38 % core saving becomes **−13 %** at PE level: the squarer's reconstruction moves work **into the accumulator**, which grows ~2.4×
- In BFP the dilution is stronger still — the reconstruction has to happen at a common exponent scale, which loads the reduction tree, leaving **−2.6 %**
- **BFP inflates the PE by ~40 %**, almost entirely in the reduction and accumulation stages

| Variant | DP8-Array | CPR-Tree | ACC-Array | PE glue | Total | vs own baseline |
|---|---|---|---|---|---|---|
| Baseline | 0.701 | 0.161 | 0.076 | 0.062 | 1.000 | — |
| Square | 0.435 | 0.159 | 0.183 | 0.093 | 0.870 | **−13.0 %** |
| Baseline-BFP | 0.724 | 0.398 | 0.202 | 0.078 | 1.402 | — |
| Square-BFP | 0.436 | 0.633 | 0.195 | 0.100 | 1.364 | **−2.6 %** |

Square-BFP block reconstruction: **0.223**

---

## Area at the grid level — the α/β tax appears

- Scope: the complete N×N grid, at **8×8** and **16×16** — the α/β generators appear as a new cost, the O(N) term
- At **8×8** the two terms almost exactly cancel: **−0.9 %** (square), **+2.6 %** (square-BFP)
- At **16×16** the N² saving pulls ahead: **−6.9 %** (square), and square-BFP reaches **parity**
- Everything that is neither PE nor α/β — dispatch, clock, control — stays under 3 % of the grid, which is why the per-PE gain eventually decides everything

**8 × 8**

| Variant | PE | α/β | Others | Total | vs own baseline |
|---|---|---|---|---|---|
| Baseline | 0.976 | — | 0.024 | 1.000 | — |
| Square | 0.849 | 0.119 | 0.022 | 0.991 | **−0.9 %** |
| Baseline-BFP | 0.980 | — | 0.020 | 1.000 | — |
| Square-BFP | 0.954 | 0.053 | 0.019 | 1.026 | **+2.6 %** |

**16 × 16**

| Variant | PE | α/β | Others | Total | vs own baseline |
|---|---|---|---|---|---|
| Baseline | 0.988 | — | 0.012 | 1.000 | — |
| Square | 0.860 | 0.060 | 0.011 | 0.931 | **−6.9 %** |
| Baseline-BFP | 0.990 | — | 0.010 | 1.000 | — |
| Square-BFP | 0.964 | 0.027 | 0.009 | 1.000 | **−0.0 %** |

---

## Power at the grid level — a larger margin than area

- Same scope and same variants, **dynamic power**
- **8×8: −8.9 %** (square), **−2.6 %** (square-BFP) · **16×16: −16.1 %** (square), **−6.4 %** (square-BFP)
- The margin is **roughly double** the area margin at every size
- Replacing multipliers with squarers removes more **toggling** than it removes **gates**

**8 × 8**

| Variant | PE | α/β | Others | Total | vs own baseline |
|---|---|---|---|---|---|
| Baseline | 0.964 | — | 0.036 | 1.000 | — |
| Square | 0.736 | 0.131 | 0.045 | 0.911 | **−8.9 %** |
| Baseline-BFP | 0.968 | — | 0.032 | 1.000 | — |
| Square-BFP | 0.868 | 0.072 | 0.035 | 0.974 | **−2.6 %** |

**16 × 16**

| Variant | PE | α/β | Others | Total | vs own baseline |
|---|---|---|---|---|---|
| Baseline | 0.981 | — | 0.019 | 1.000 | — |
| Square | 0.749 | 0.067 | 0.023 | 0.839 | **−16.1 %** |
| Baseline-BFP | 0.984 | — | 0.016 | 1.000 | — |
| Square-BFP | 0.881 | 0.037 | 0.018 | 0.936 | **−6.4 %** |

---

## Area scaling — the O(N²) saving against the O(N) tax

- % area gain against the matching baseline, as the grid grows
- **Crossover: N ≈ 7.4** (square) and **N ≈ 15.9** (square-BFP) — below it the shared hardware is not yet amortized
- **Asymptotes: −13.0 % and −2.6 %** — exactly the per-PE gains from the PE-level chart
- The asymptote is the design's true limit: it is what you get when the α/β overhead becomes negligible

| N | Square | Square-BFP |
|---|---|---|
| 2 | +32.1 % | +17.0 % |
| 4 | +10.6 % | +7.6 % |
| 6 | +2.9 % | +4.2 % |
| 8 | **−0.9 %** | **+2.6 %** |
| 12 | −4.9 % | +0.8 % |
| 16 | **−6.9 %** | **−0.0 %** |
| 24 | −8.9 % | −0.9 % |
| 32 | −9.9 % | −1.3 % |
| 48 | −11.0 % | −1.8 % |
| 64 | −11.5 % | −2.0 % |
| 96 | −12.0 % | −2.2 % |
| 128 | −12.2 % | −2.3 % |
| ∞ | **−13.0 %** | **−2.6 %** |

Zero crossings: **N = 7.40** (square) · **N = 15.92** (square-BFP)

---

## Power scaling — earlier crossover, larger gain

- Same construction, **dynamic power**
- **Crossover: N ≈ 4.9** (square) and **N ≈ 6.0** (square-BFP) — both **earlier than area**
- **Asymptotes: −23.7 % and −10.4 %** — roughly double the area asymptotes
- Between the power crossover and the area crossover, the square **buys energy at no area cost**

| N | Square | Square-BFP |
|---|---|---|
| 2 | +29.6 % | +18.3 % |
| 4 | +4.9 % | +4.8 % |
| 6 | −4.2 % | −0.1 % |
| 8 | **−8.9 %** | **−2.6 %** |
| 12 | −13.7 % | −5.1 % |
| 16 | **−16.1 %** | **−6.4 %** |
| 24 | −18.6 % | −7.7 % |
| 32 | −19.9 % | −8.4 % |
| 48 | −21.1 % | −9.1 % |
| 64 | −21.8 % | −9.4 % |
| 96 | −22.4 % | −9.7 % |
| 128 | −22.7 % | −9.9 % |
| ∞ | **−23.7 %** | **−10.4 %** |

Zero crossings: **N = 4.88** (square) · **N = 5.97** (square-BFP)

---

## Conclusion

- **Hardware sharing works as a strategy.** Restructure the computation so part of it depends on one operand only, hoist that part out of the compute unit: **O(N)** cost against an **O(N²)** saving
- **The square identity is one instance of it** — a·b = ½[(a+b)² − a² − b²], with α shared per row and β shared per column
- **Measured on ASAP7**, four design variants, all 11 operating modes:
  - 16×16: **−6.9 % area**, **−16.1 % power**; the BFP variant reaches area parity at **−6.4 % power**
  - Asymptotically: **−13 % area**, **−24 % power**
- **Bit-exact** to the reference — the gain carries no accuracy cost
- **The design guide is the crossover, not the average:** power turns positive at N ≈ 5, area at N ≈ 7. Below that, shared hardware is not amortized
