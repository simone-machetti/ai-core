# Grid Scaling — Square vs Baseline, Square-BFP / Bit-Plane-A / Bit-Plane-B / NR4SD vs Baseline-BFP

Area and dynamic-power gain of each variant against its own baseline as the grid grows, from 2×2 to 128×128 — the crossover, and the limit the design converges to.

## Purpose

[Synthesis Area](syn_area.md) and [Synthesis Power](syn_pwr.md) report two grid sizes each. Two points are enough to say the square wins at 16×16 and roughly breaks even at 8×8, but not enough to answer the two questions a designer actually asks: **where does it turn positive**, and **how much is there to gain if the grid were larger**.

Both follow from the same structure, and all five variants share it. The square replaces every PE's multipliers with squarers — an **N²** saving — and pays for it with per-row α and per-column β generators — an **N** cost. The bit-plane replaces Booth with bit-plane selection — a smaller **N²** saving — and pays for it by enlarging the existing column dispatcher — a much smaller **N** cost. The NR4SD hybrid replaces Booth's three partial products per lane with two — an **N²** saving of the same kind — and pays for it by moving the recoders into that same column dispatcher — the smallest **N** cost of all. Either way the ratio against the baseline is a function of N alone:

```
gain(N) = [ N²·pe_sqr + N·(disp_sqr + α + β) + const ] / [ N²·pe + N·disp + const ] − 1
```

which starts positive (the edge strips dominate), crosses zero once, and tends to the per-PE ratio as the O(N) terms vanish against the O(N²) ones. How early it crosses is set entirely by the ratio of the two coefficients — which is why the bit-plane and NR4SD variants, whose N term is one widened dispatcher rather than two whole arrays, cross before 2×2.

## Method

No new synthesis. The curves are the **same instance-count model** that assembles the bars in [Synthesis Area](syn_area.md) and [Synthesis Power](syn_pwr.md) — PE and per-PE clock gate ×N², dispatch and α/β ×N, row/column clock gates ×2N, control/const/glue ×1 — evaluated over a range of N instead of at two fixed sizes. The per-component areas and VCD-annotated unit powers are unchanged, so nothing new is measured and nothing is refitted.

That makes the relationship exact rather than approximate: the 8×8 and 16×16 bars of those two experiments are **two points on these curves by construction**. Checked numerically — the model reproduces both charts' totals for all seven variants, in area and in power, to a delta of `0.000000`.

The chart is [line_syn_scaling.py](../../doc/charts/line_syn_scaling.py), which writes `line_syn_scaling_area.png` and `line_syn_scaling_pwr.png`; numbers land in `doc/data/res_syn_scaling.xlsx`. The y axis is percent gain, so the charts carry no absolute units.

## Results

Percent gain against the matching baseline; negative means the variant wins.

| N      | Area, square | Area, square-BFP | Area, bpl-A | Area, bpl-B | Area, nr4sd | Power, square | Power, square-BFP | Power, bpl-A | Power, bpl-B | Power, nr4sd |
| ------ | ------------ | ---------------- | ----------- | ----------- | ----------- | ------------- | ----------------- | ------------ | ------------ | ------------ |
| 2      | +32.1        | +17.0            | **−2.1**    | **−12.1**   | **−11.4**   | +29.6         | +18.3             | +2.1         | **−11.7**    | **−1.95**    |
| 4      | +10.6        | +7.6             | −2.9        | −13.1       | −12.1       | +4.9          | +4.8              | +0.5         | −13.5        | −2.55        |
| 6      | +2.9         | +4.2             | −3.1        | −13.5       | −12.3       | −4.2          | −0.1              | −0.0         | −14.2        | −2.76        |
| **8**  | **−0.9**     | **+2.6**         | **−3.3**    | **−13.7**   | **−12.4**   | **−8.9**      | **−2.6**          | **−0.30**    | **−14.5**    | **−2.87**    |
| 12     | −4.9         | +0.8             | −3.4        | −13.9       | −12.6       | −13.7         | −5.1              | −0.60        | −14.9        | −2.98        |
| **16** | **−6.9**     | **−0.0**         | **−3.5**    | **−13.9**   | **−12.6**   | **−16.1**     | **−6.4**          | **−0.75**    | **−15.0**    | **−3.04**    |
| 24     | −8.9         | −0.9             | −3.5        | −14.0       | −12.7       | −18.6         | −7.7              | −0.90        | −15.2        | −3.10        |
| 32     | −9.9         | −1.3             | −3.6        | −14.1       | −12.7       | −19.9         | −8.4              | −0.98        | −15.3        | −3.12        |
| 48     | −11.0        | −1.8             | −3.6        | −14.1       | −12.8       | −21.1         | −9.1              | −1.05        | −15.4        | −3.15        |
| 64     | −11.5        | −2.0             | −3.6        | −14.2       | −12.8       | −21.8         | −9.4              | −1.09        | −15.4        | −3.17        |
| 96     | −12.0        | −2.2             | −3.7        | −14.2       | −12.8       | −22.4         | −9.7              | −1.13        | −15.5        | −3.18        |
| 128    | −12.2        | −2.3             | −3.7        | −14.2       | −12.8       | −22.7         | −9.9              | −1.15        | −15.5        | −3.19        |
| **∞**  | **−13.0**    | **−2.6**         | **−3.7**    | **−14.2**   | **−12.8**   | **−23.7**     | **−10.4**         | **−1.21**    | **−15.6**    | **−3.21**    |

Crossovers and asymptotes:

| Pair                            | Area crossover | Area asymptote | Power crossover | Power asymptote |
| ------------------------------- | -------------- | -------------- | --------------- | --------------- |
| Square vs Baseline              | N = 7.40       | −13.0 %        | N = 4.88        | −23.7 %         |
| Square-BFP vs Baseline-BFP      | N = 15.92      | −2.6 %         | N = 5.97        | −10.4 %         |
| Bit-Plane-A BFP vs Baseline-BFP | **N = 1.00**   | −3.7 %         | N = 5.92        | −1.2 %          |
| Bit-Plane-B BFP vs Baseline-BFP | **N = 1.00**   | **−14.2 %**    | **N = 1.00**    | **−15.6 %**     |
| NR4SD BFP vs Baseline-BFP       | **N = 1.00**   | −12.8 %        | **N = 1.00**    | −3.2 %          |

Five readings:

- **The asymptote is the per-PE ratio.** −13.0 % and −2.6 % in area are exactly the PE totals of [Intra-PE Area](syn_pe_area.md); −23.7 % and −10.4 % in power are the per-PE power ratios. Nothing is fitted — as N grows the O(N) α/β term vanishes against the O(N²) tile term and the grid ratio collapses onto the tile ratio. The scaling chart is the O(N²)-vs-O(N) argument made visible, and the PE-level chart is its limit.
- **Power crosses over before area** — N ≈ 4.9 against N ≈ 7.4 for the square, N ≈ 6.0 against N ≈ 15.9 for square-BFP. Replacing multipliers with squarers removes more toggling than it removes gates. Between the two crossovers the square buys energy at no area cost.
- **Square-BFP converges early but shallow.** Its power crossover is close to the square's, but its area asymptote is only −2.6 %, so past ~32×32 there is little left to gain on area — the BFP PE is already ~40 % larger and the squarer's absolute per-tile saving is correspondingly smaller.
- **Bit-plane inverts the pattern: area crosses first, power last.** It is the only variant that is already ahead in area at 2×2 (`N = 1.00`), because its N term is a single widened dispatcher (+149.90 µm²/column) rather than two extra arrays — the curve is essentially flat, at −2.1 % from the very first point to −3.7 % in the limit. In power it behaves like the others, crossing at N ≈ 5.9, but with an asymptote of only −1.2 %: bit-plane selection removes gates far more effectively than it removes toggling. It is therefore the **safe** variant at small N and the **shallow** one at large N — the opposite trade to square-BFP, which is the one to pick past ~32×32 on power.
- **NR4SD has bit-plane B's shape at a fraction of its power depth.** Area crosses at `N = 1.00` and is essentially flat — −11.4 % at 2×2 to −12.8 % in the limit, within 1.4 pp of bit-plane B at every N — because its N term is the smallest of all (+60.58 µm²/column, a +13 % dispatcher). Power crosses at `N = 1.00` too, making it the second variant after bit-plane B to be ahead on both axes from the first point, but its asymptote is only −3.2 %: dropping Booth's third row removes a third of the DP8's compressor rows and 39 % of its full adders, which area rewards in full and power barely, since that row is already a constant zero in the whole-int4 modes and the hybrid broadcasts a wider code bus in every mode ([Per-Mode Synthesis Power](syn_mode_pwr.md)). It shares bit-plane B's *safety* — no crossover to wait for, on either axis — without its power *depth*, so between the two the choice is bit-plane B at every N; NR4SD's case is that it keeps Booth's 20-bit DP8 contract and the baseline tree intact.

## Caveats

Everything upstream applies. The per-component figures are measured; the grid totals at every N — including 8×8 and 16×16 — are **assembled** from them, so these curves are a model over measured inputs, not measurements of a synthesized grid. Power additionally inherits the hostile uniform-random stimulus of [Synthesis Power](syn_pwr.md), and the wide per-mode spread of [Per-Mode Synthesis Power](syn_mode_pwr.md) means a single crossover figure is a workload average, not a guarantee for any one mode — least of all for the bit-plane variant, whose ±0.3 % grid-average hides a per-mode range from −12 % to +23 %, and to a lesser degree for the NR4SD variant, whose −2.9 % spans +5.6 % (mode 1) to −6.4 % (mode 12).

The model also assumes the per-component figures are N-independent — true by construction here, since every instance is the same hardened block seeing an operand stream of the same statistics, but it does not capture what a real floorplan would add at large N (longer broadcast wires, deeper buffering, clock-tree growth). Those come from P&R, not from this model.
