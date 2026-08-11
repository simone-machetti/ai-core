# Synthesis Power — Baseline / Square / Baseline-BFP / Square-BFP / Bit-Plane BFP

VCD-annotated dynamic-power comparison of the five PE-grid variants — [top_NxN](../architectures/top_NxN.md), [top_NxN_sqr](../architectures/top_NxN_sqr.md), [top_NxN_bfp](../architectures/top_NxN_bfp.md), [top_NxN_sqr_bfp](../architectures/top_NxN_sqr_bfp.md), [top_NxN_bpl_bfp](../architectures/top_NxN_bpl_bfp.md) — measured on the complete synthesized 2×2 grids and assembled from per-component unit power for 8×8 and 16×16.

## Purpose

[Synthesis Area](syn_area.md) established the axes: the square trades an N² per-PE saving against an N α/β overhead (crossover ≈ 8×8, ≈ 16×16 inside BFP), the bit-plane trades a smaller N² saving against a much smaller N dispatcher overhead (crossover N = 1), and the BFP sideband inflates the PE ~40 %. Power need not track area — the α/β generators run every cycle, the squarer's toggle profile is not the multiplier's, and a bit-plane multiplexer array is not a Booth array — so this experiment measures where each **power** crossover actually lands, each variant against its own baseline.

## Method

Four passes. Passes A and B are those of [Synthesis Area](syn_area.md) at N=2 — each component synthesized once (`OUT_DIR=<module>_syn`), then the grid synthesized with those netlists linked through `BLACKBOX_MODULES`, which is what makes the per-instance power report possible. Pass C runs gate-level simulation of the netlist to dump switching activity; pass D annotates that activity onto the netlist in OpenSTA.

```
# pass C - gate-level simulation, dumps activity.vcd
make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp OUT_DIR=top_2x2_sqr_bfp_post_syn_sim \
    NETLIST_DIR=top_2x2_sqr_bfp_syn TB=tb_top_NxN_sqr_bfp_pwr CLK_PERIOD_NS=10 VCD=1

# pass D - VCD-annotated power
make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp OUT_DIR=top_2x2_sqr_bfp_post_syn_dpa \
    NETLIST_DIR=top_2x2_sqr_bfp_syn VCD_DIR=top_2x2_sqr_bfp_post_syn_sim \
    TB=tb_top_NxN_sqr_bfp_pwr CLK_PERIOD_NS=10 BLACKBOX_MODULES="pe_sqr_bfp ctrl_sqr …"
```

Stimulus is the five `tb/tb_top_NxN[_sqr|_bpl][_bfp]_pwr.sv` benches — 100 uniform-random operand sets per mode, streamed one per clock with every row and column enabled, single-shot only (`sel_acc` low, `acc` zero, no scaling), all 11 modes back to back with no reset between them so the VCD holds one continuous busy window. The benches are byte-identical apart from the DUT, so the comparison is against the same stimulus. `CLK_PERIOD_NS=10` (100 MHz); dumping starts after reset deassertion, so the reset transient is not charged to the average. OpenSTA cannot parse Verilator's `$var real` / `r…` lines, so the flow strips them from the VCD before `read_vcd`; annotation is then complete (**0 unannotated pins**) on all five variants.

All commands are in [run_syn_pwr.sh](../../scripts/run_syn_pwr.sh). Numbers land in `doc/data/res_syn_pwr.xlsx` and `doc/charts/hist_syn_pwr.png`; the chart is normalized to the baseline grid of the same size, so it carries ratios rather than absolute mW.

### Why 2×2 is measured and the larger grids are assembled

Verilator elaborates every instance of a gate-level netlist, so gate-level simulation memory scales as N² — about 0.4 GB at 2×2 but tens of GB at 8×8 and hundreds at 16×16 (more for the BFP netlists). So the 8×8 / 16×16 figures are **assembled**: each component's unit power is taken from the 2×2 per-instance report and multiplied by its instance count. Unlike area, power is activity-dependent; what makes the assembly valid is that the grid keeps each instance's activity identical regardless of N — every PE sees an operand stream of the same statistics. **Treat 8×8 and 16×16 as projections, not measurements.** [Synthesis Area](syn_area.md) assembles its two grid sizes the same way and for the same reason, so both experiments report measured components and modelled grids; [Grid Scaling](syn_scaling.md) evaluates that shared model over a range of N.

## Instance counts

Same counts as [Synthesis Area](syn_area.md), except the clock gates are **split by position** — a per-PE gate (N²) and a per-row/column gate (2N) are the same cell but see different enable activity, so they are reported separately. The BFP variants add the per-row/column exponent dispatchers ([disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) / `_b` and their `_sqr_bfp` forms, ×N each); the square variants add the α/β generators (×N) and `const` (×1). The bit-plane variant adds **nothing** — it is the baseline-BFP count with `disp_array_b` swapped for [disp_array_b_bpl_bfp](../modules/disp_array_b_bpl_bfp.md).

## Results

Per-component unit power from the 2×2 runs, mW:

| Component           | Baseline | Square  | Baseline-BFP | Square-BFP | Bit-Plane BFP |
| ------------------- | -------- | ------- | ------------ | ---------- | ------------- |
| `ctrl` / `ctrl_sqr` | 0.00127  | 0.00177 | 0.00136      | 0.00162    | 0.00137       |
| `const`             | —        | 0.00001 | —            | 0.00002    | —             |
| `disp_array_a`      | 0.10100  | 0.12300 | 0.10200      | 0.12250    | 0.12200       |
| `disp_array_b`      | 0.09975  | 0.10700 | 0.10100      | 0.10800    | **0.14850**   |
| `disp_array_exp_a`  | —        | —       | 0.01380      | 0.01020    | 0.01370       |
| `disp_array_exp_b`  | —        | —       | 0.01610      | 0.01665    | 0.01615       |
| `pe_array_alpha`    | —        | 0.40000 | —            | 0.29050    | —             |
| `pe_array_beta`     | —        | 0.36500 | —            | 0.27200    | —             |
| `pe` (per variant)  | 0.68225  | 0.51700 | 0.91850      | 0.82000    | **0.90700**   |
| `icg` (per PE)      | 0.02080  | 0.01970 | 0.02610      | 0.02620    | 0.02620       |
| `icg` (per row/col) | 0.00591  | 0.01490 | 0.00673      | 0.00673    | 0.00673       |

Note `disp_array_a` — the *same* netlist — reports 0.122 mW in the bit-plane grid against 0.102 in the baseline-BFP grid. Its A bus drives 32 bit-plane multiplexer selects per DP8 instead of Booth encoders, a different capacitive load, and OpenSTA charges net switching power to the driver.

Grid totals, mW:

| Grid  | Baseline | Square  | Baseline-BFP | Square-BFP | Bit-Plane BFP | Square/Base | Sqr-BFP/Base-BFP | Bpl-BFP/Base-BFP | Basis     |
| ----- | -------- | ------- | ------------ | ---------- | ------------- | ----------- | ---------------- | ---------------- | --------- |
| 2×2   | 3.240    | 4.200   | 4.272        | 5.053      | 4.362         | +29.6 %     | +18.3 %          | +2.1 %           | measured  |
| 8×8   | 46.698   | 42.551  | 62.427       | 60.825     | 62.237        | −8.9 %      | −2.6 %           | −0.30 %          | assembled |
| 16×16 | 183.385  | 153.796 | 245.761      | 229.962    | 243.922       | −16.1 %     | −6.4 %           | −0.75 %          | assembled |

Three readings, each against its own baseline:

- **Square vs baseline** — the square costs 29.6 % more at 2×2 but saves **8.9 % at 8×8 and 16.1 % at 16×16**. The per-PE (`pe` + per-PE `icg`) saving is 0.16635 mW/tile (−23.7 % per PE) against 0.765 mW per row+column for the α/β generators, putting the **power crossover at N ≈ 4.9** — the square wins from 5×5 — well *before* the area crossover at N = 7.5, and the 8×8 power margin (−8.9 %) is far larger than the area margin (−0.9 %). Replacing a multiplier array with a squarer array removes more toggling than it removes gates; the ratio tends to ≈ 0.76.
- **Square-BFP vs baseline-BFP** — the same pattern, softened: +18.3 % at 2×2, **−2.6 % at 8×8, −6.4 % at 16×16**, crossover **N ≈ 6.0** (wins from 6×6), tending to ≈ 0.90. The BFP PE toggles ~35 % more, so the squarer's per-tile power saving shrinks to 0.098 mW/tile; but the **tree-less** α/β generators cost only 0.5625 mW per row+column (vs the square's 0.765), keeping the crossover early.

- **Bit-plane BFP vs baseline-BFP** — the mirror image of its area result: +2.1 % at 2×2, **−0.30 % at 8×8, −0.75 % at 16×16**, crossover **N ≈ 5.9**, tending to only ≈ 0.988 (−1.2 %). Where area crosses over at N = 1, power does not cross until 6×6, and the asymptote is a tenth of the area asymptote. Both halves of the trade are worse in power than in area: the per-PE saving is 0.0114 mW/tile (**−1.2 %** per PE, against −3.7 % in area), while the dispatcher's overhead is **+47 %** power (0.1485 vs 0.101 mW) against +32 % area — 0.0674 mW per row+column. Replacing Booth with bit-plane selection removes gates more effectively than it removes toggling: the 32 multiplexers per DP8 switch on A's bit planes every cycle, and the pair-sum adders that moved to the dispatcher now toggle there once per column instead of going quiet inside idle PEs.

The BFP sideband costs ~34 % power on both axes (`Baseline-BFP/Baseline ≈ 1.34` at 8×8 and 16×16), dominated by the aligners in the PE.

Split by category at 8×8 (PE includes its per-PE clock gate), mW:

| Category | Baseline | Square | Baseline-BFP | Square-BFP | Bit-Plane BFP |
| -------- | -------- | ------ | ------------ | ---------- | ------------- |
| PE       | 45.00    | 34.35  | 60.45        | 54.16      | 59.72         |
| α/β      | 0.00     | 6.12   | 0.00         | 4.50       | 0.00          |
| Dispatch | 1.61     | 1.84   | 1.86         | 2.06       | 2.40          |
| Clock    | 0.10     | 0.24   | 0.11         | 0.11       | 0.11          |

The α/β generators are the whole of the square overhead and are unconditionally active (they run every cycle regardless of mode), which is why the 2×2 penalty exists and why the crossover exists at all — and why the tree-less BFP generators, which toggle less, pull the square-BFP crossover in.

## Cost and reproduction

Pass C dominates, and essentially all of it is Verilator **compiling** the netlist, not simulating it — ~1100 stimulus cycles run in seconds once the binary exists, so a longer or richer stimulus is nearly free. `read_vcd` is markedly **sublinear** in VCD size (most of the cost is per-pin bookkeeping, not per-transition). Passes A/B are shared with [Synthesis Area](syn_area.md) and need not be rerun if that experiment has already run. Nothing here needs swap at 2×2; the BFP netlists are larger but still fit. Extending the *measurement* past 2×2 is a compile-time wall, not a simulate-time one — 16×16 is out of reach for Verilator at gate level, which is why the larger sizes are assembled.
