# Grid Scaling — Square vs Baseline and Square-BFP vs Baseline-BFP

Area and dynamic-power gain of each square variant against its own baseline as the grid grows, from 2×2 to 128×128 — the crossover, and the limit the design converges to.

## Purpose

[Synthesis Area](syn_area.md) and [Synthesis Power](syn_pwr.md) report two grid sizes each. Two points are enough to say the square wins at 16×16 and roughly breaks even at 8×8, but not enough to answer the two questions a designer actually asks: **where does it turn positive**, and **how much is there to gain if the grid were larger**.

Both follow from the same structure. The square replaces every PE's multipliers with squarers — an **N²** saving — and pays for it with per-row α and per-column β generators — an **N** cost. So the ratio against the baseline is a function of N alone:

```
gain(N) = [ N²·pe_sqr + N·(disp_sqr + α + β) + const ] / [ N²·pe + N·disp + const ] − 1
```

which starts positive (the edge strips of generators dominate), crosses zero once, and tends to the per-PE ratio as the O(N) terms vanish against the O(N²) ones.

## Method

No new synthesis. The curves are the **same instance-count model** that assembles the bars in [Synthesis Area](syn_area.md) and [Synthesis Power](syn_pwr.md) — PE and per-PE clock gate ×N², dispatch and α/β ×N, row/column clock gates ×2N, control/const/glue ×1 — evaluated over a range of N instead of at two fixed sizes. The per-component areas and VCD-annotated unit powers are unchanged, so nothing new is measured and nothing is refitted.

That makes the relationship exact rather than approximate: the 8×8 and 16×16 bars of those two experiments are **two points on these curves by construction**. Checked numerically — the model reproduces both charts' totals for all four variants, in area and in power, to a delta of `0.000000`.

The chart is [line_syn_scaling.py](../../doc/charts/line_syn_scaling.py), which writes `line_syn_scaling_area.png` and `line_syn_scaling_pwr.png`; numbers land in `doc/data/res_syn_scaling.xlsx`. The y axis is percent gain, so the charts carry no absolute units.

## Results

Percent gain against the matching baseline; negative means the square wins.

| N       | Area, square | Area, square-BFP | Power, square | Power, square-BFP |
| ------- | ------------ | ---------------- | ------------- | ----------------- |
| 2       | +32.1        | +17.0            | +29.6         | +18.3             |
| 4       | +10.6        | +7.6             | +4.9          | +4.8              |
| 6       | +2.9         | +4.2             | −4.2          | −0.1              |
| **8**   | **−0.9**     | **+2.6**         | **−8.9**      | **−2.6**          |
| 12      | −4.9         | +0.8             | −13.7         | −5.1              |
| **16**  | **−6.9**     | **−0.0**         | **−16.1**     | **−6.4**          |
| 24      | −8.9         | −0.9             | −18.6         | −7.7              |
| 32      | −9.9         | −1.3             | −19.9         | −8.4              |
| 48      | −11.0        | −1.8             | −21.1         | −9.1              |
| 64      | −11.5        | −2.0             | −21.8         | −9.4              |
| 96      | −12.0        | −2.2             | −22.4         | −9.7              |
| 128     | −12.2        | −2.3             | −22.7         | −9.9              |
| **∞**   | **−13.0**    | **−2.6**         | **−23.7**     | **−10.4**         |

Crossovers and asymptotes:

| Pair                          | Area crossover | Area asymptote | Power crossover | Power asymptote |
| ----------------------------- | -------------- | -------------- | --------------- | --------------- |
| Square vs Baseline            | N = 7.40       | −13.0 %        | N = 4.88        | −23.7 %         |
| Square-BFP vs Baseline-BFP    | N = 15.92      | −2.6 %         | N = 5.97        | −10.4 %         |

Three readings:

- **The asymptote is the per-PE ratio.** −13.0 % and −2.6 % in area are exactly the PE totals of [Intra-PE Area](syn_pe_area.md); −23.7 % and −10.4 % in power are the per-PE power ratios. Nothing is fitted — as N grows the O(N) α/β term vanishes against the O(N²) tile term and the grid ratio collapses onto the tile ratio. The scaling chart is the O(N²)-vs-O(N) argument made visible, and the PE-level chart is its limit.
- **Power crosses over before area** — N ≈ 4.9 against N ≈ 7.4 for the square, N ≈ 6.0 against N ≈ 15.9 for square-BFP. Replacing multipliers with squarers removes more toggling than it removes gates. Between the two crossovers the square buys energy at no area cost.
- **Square-BFP converges early but shallow.** Its power crossover is close to the square's, but its area asymptote is only −2.6 %, so past ~32×32 there is little left to gain on area — the BFP PE is already ~40 % larger and the squarer's absolute per-tile saving is correspondingly smaller.

## Caveats

Everything upstream applies. The per-component figures are measured; the grid totals at every N — including 8×8 and 16×16 — are **assembled** from them, so these curves are a model over measured inputs, not measurements of a synthesized grid. Power additionally inherits the hostile uniform-random stimulus of [Synthesis Power](syn_pwr.md), and the wide per-mode spread of [Per-Mode Synthesis Power](syn_mode_pwr.md) means a single crossover figure is a workload average, not a guarantee for any one mode.

The model also assumes the per-component figures are N-independent — true by construction here, since every instance is the same hardened block seeing an operand stream of the same statistics, but it does not capture what a real floorplan would add at large N (longer broadcast wires, deeper buffering, clock-tree growth). Those come from P&R, not from this model.
