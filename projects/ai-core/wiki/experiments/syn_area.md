# Synthesis Area — Baseline / Square / Baseline-BFP / Square-BFP / Bit-Plane BFP

Cell-area comparison of the five PE-grid variants — [top_NxN](../architectures/top_NxN.md) (baseline), [top_NxN_sqr](../architectures/top_NxN_sqr.md) (square), [top_NxN_bfp](../architectures/top_NxN_bfp.md) (baseline-BFP), [top_NxN_sqr_bfp](../architectures/top_NxN_sqr_bfp.md) (square-BFP) and [top_NxN_bpl_bfp](../architectures/top_NxN_bpl_bfp.md) (bit-plane BFP) — at 8×8 and 16×16, assembled from per-component measurements.

## Purpose

Three axes, all of them the same trade in different proportions: move work out of the N² tile and pay for it once per row or column. The **square** axis replaces each PE's multipliers with squarers (an N² PE saving) but pays for per-row/per-column α/β correction generators (an N overhead), so which wins depends on grid size. The **BFP** axis adds an exponent sideband — per-lane aligners in the PE and exponent dispatchers around it — a fixed inflation of the PE that both non-square and square pay. The **bit-plane** axis replaces Booth recoding of B with bit-plane selection on A and hoists the pairwise B sums into the column dispatcher — the same N²→N move as α/β, but the overhead is one enlarged dispatcher rather than two extra arrays. The interesting questions are whether the square identity still pays *inside* the BFP datapath, where the PE is already ~40 % larger, and how cheaply the bit-plane variant buys its per-tile saving. Absolute µm² is not the deliverable; the ratios (each variant against **its own baseline**) are.

## Method

Two passes per variant, both at **N = 2**. Pass A synthesizes each component once on its own (`OUT_DIR=<module>_syn`). Pass B synthesizes the 2×2 grid, linking those netlists through `BLACKBOX_MODULES` rather than re-elaborating every instance — the netlist carries one shared module per component (the hierarchy a tiled place-and-route wants: the PE is the replicated tile, hardened once and placed N² times), and the residual top-level area is the fixed glue term.

```
# pass A - one run per component
make syn PROJECT=ai-core TOP_LEVEL=<module> OUT_DIR=<module>_syn

# pass B - the 2x2 grid (blackbox list is per variant)
make syn PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp OUT_DIR=top_2x2_sqr_bfp_syn PARAMS="N=2" \
    BLACKBOX_MODULES="pe_sqr_bfp ext_inject_sqr_bfp ctrl_sqr const_sqr_bfp \
                      disp_array_a_sqr disp_array_b_sqr disp_array_exp_a_sqr_bfp disp_array_exp_b_sqr_bfp \
                      pe_array_alpha_sqr_bfp pe_array_beta_sqr_bfp icg"
```

The 8×8 and 16×16 figures are then **assembled analytically** from the per-component areas and a per-N instance-count model — PE and per-PE clock gate ×N², dispatch and α/β ×N, row/column clock gates ×2N, control/const/glue ×1 — in [hist_syn_area.py](../../doc/charts/hist_syn_area.py). **No 8×8 or 16×16 grid is ever synthesized.** The assembly is exact rather than approximate: every component has a `localparam`-only interface, so its area does not depend on N, and only the grid size would need `-G` at all. The earlier method did elaborate the full grids, which cost ~26 GB at 16×16 for figures the count model reproduces from a 2×2 run.

Library is `asap7sc7p5t` RVT TT. Pass B resolves each blackboxed module at `imp/<module>_syn/output/netlist.v` (the `bb_netlist` helper searches `<module>_syn` first), hence the `_syn` suffix in pass A. Interconnect, clock tree and placement utilization are out of scope and come later from P&R.

All commands are in [run_syn_area.sh](../../scripts/run_syn_area.sh). Numbers land in `doc/data/res_syn_area.xlsx` and `doc/charts/hist_syn_area.png`; the chart is normalized to the baseline grid of the same size, so it carries ratios rather than absolute mm². [Grid Scaling](syn_scaling.md) evaluates the same model over a range of N, and [Intra-PE Area](syn_pe_area.md) opens the PE up into its DP8 array, tree and accumulator.

## Instance counts

| Component                                                                                               | Baseline | Square | Baseline-BFP | Square-BFP     | Bit-Plane BFP | ×count  |
| ------------------------------------------------------------------------------------------------------- | -------- | ------ | ------------ | -------------- | ------------- | ------- |
| [ctrl](../modules/ctrl.md) / [ctrl_sqr](../modules/ctrl_sqr.md)                                         | ✓        | ✓      | ✓ (`ctrl`)   | ✓ (`ctrl_sqr`) | ✓ (`ctrl`)    | 1       |
| [const_sqr](../modules/const_sqr.md) / [const_sqr_bfp](../modules/const_sqr_bfp.md)                     |          | ✓      |              | ✓              |               | 1       |
| [disp_array_a](../modules/disp_array_a.md) / `_sqr`                                                     | ✓        | ✓      | ✓            | ✓              | ✓             | N       |
| [disp_array_b](../modules/disp_array_b.md) / `_sqr` / [`_bpl_bfp`](../modules/disp_array_b_bpl_bfp.md)  | ✓        | ✓      | ✓            | ✓              | ✓             | N       |
| [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) / `_sqr_bfp`                                 |          |        | ✓            | ✓              | ✓             | N       |
| [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md) / `_sqr_bfp`                                 |          |        | ✓            | ✓              | ✓             | N       |
| [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md) / [`_bfp`](../modules/pe_array_alpha_sqr_bfp.md) |          | ✓      |              | ✓              |               | N       |
| [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md) / [`_bfp`](../modules/pe_array_beta_sqr_bfp.md)    |          | ✓      |              | ✓              |               | N       |
| [pe](../modules/pe.md) / `_sqr` / `_bfp` / `_sqr_bfp` / [`_bpl_bfp`](../modules/pe_bpl_bfp.md)          | ✓        | ✓      | ✓            | ✓              | ✓             | N²      |
| [icg](../modules/icg.md)                                                                                | ✓        | ✓      | ✓            | ✓              | ✓             | N² + 2N |

The bit-plane column is the plain BFP column with `disp_array_b` swapped for the larger [disp_array_b_bpl_bfp](../modules/disp_array_b_bpl_bfp.md) — it has **no N-term array of its own**, which is what makes its crossover so early. The clock-gate count is identical on all five sides — one per PE, one per row, one per column: 80 at 8×8, 288 at 16×16 (each [icg](../modules/icg.md) carries a real 0.262 µm²). The square-BFP PE folds its `−α`/`−β`/`C` per DP8 in [ext_inject_sqr_bfp](../modules/ext_inject_sqr_bfp.md), which is inside `pe_sqr_bfp` (counted in the PE, not separately). Top-level glue — the `sel_acc`/const pipeline and the operand/control fan-out — is the only term measured rather than linked.

## Results

Per-component unit areas from pass A, µm²:

| Component            | Baseline | Square   | Baseline-BFP | Square-BFP | Bit-Plane BFP |
| -------------------- | -------- | -------- | ------------ | ---------- | ------------- |
| `ctrl` / `ctrl_sqr`  | 8.879    | 9.769    | 8.879        | 9.769      | 8.879         |
| `const`              | —        | 3.747    | —            | 4.184      | —             |
| `disp_array_a`       | 277.734  | 366.118  | 277.734      | 366.118    | 277.734       |
| `disp_array_b`       | 466.327  | 332.686  | 466.327      | 332.686    | **616.224**   |
| `disp_array_exp_a`   | —        | —        | 42.924       | 41.990     | 42.924        |
| `disp_array_exp_b`   | —        | —        | 75.174       | 68.584     | 75.174        |
| `pe_array_alpha`     | —        | 1962.235 | —            | 1226.688   | —             |
| `pe_array_beta`      | —        | 1753.682 | —            | 1070.755   | —             |
| `pe` (per variant)   | 3816.519 | 3320.303 | 5345.990     | 5204.929   | **5148.898**  |
| `icg`                | 0.262    | 0.262    | 0.262        | 0.262      | 0.262         |

Grid totals, µm²:

| Grid  | Baseline  | Square    | Baseline-BFP | Square-BFP | Bit-Plane BFP | Square/Base | Sqr-BFP/Base-BFP | Bpl-BFP/Base-BFP |
| ----- | --------- | --------- | ------------ | ---------- | ------------- | ----------- | ---------------- | ---------------- |
| 8×8   | 250241.37 | 247872.09 | 349072.30    | 358008.45  | 337660.54     | −0.9 %      | **+2.6 %**       | **−3.3 %**       |
| 16×16 | 989020.11 | 920742.70 | 1382454.30   | 1382263.94 | 1334399.96    | −6.9 %      | **−0.0 %**       | **−3.5 %**       |

Three readings, each against its own baseline:

- **Square vs baseline** — 1.5 %→0.9 % smaller at 8×8, 7.3 %→6.9 % at 16×16 (the re-run trims the old figures slightly). The per-PE saving is an N² term (496.22 µm²/tile) against the α/β generators' N term (3670.66 µm²/row+col), so 8×8 is the crossover and the ratio tends to `pe_sqr/pe = 0.870`.
- **Square-BFP vs baseline-BFP** — the square identity **still pays inside BFP**, but the crossover moves out to **N ≈ 16**: +2.6 % at 8×8, exact **parity at 16×16**, tending to `pe_sqr_bfp/pe_bfp = 0.974` (−2.6 %). Two things push the crossover from 8 to 16: the BFP sideband inflates the PE ~40 % (`pe_bfp` is 5345.99 vs `pe` 3816.52), so the squarer's absolute per-tile saving shrinks to 141.06 µm²/tile; but the **tree-less** α/β generators ([pe_array_alpha_sqr_bfp](../modules/pe_array_alpha_sqr_bfp.md) 1226.69, [`_beta`](../modules/pe_array_beta_sqr_bfp.md) 1070.76 — 37–39 % smaller than the square's tree'd generators) cut the N overhead to 2244.66 µm²/row+col. Crossover `N ≈ 2244.66 / 141.06 ≈ 16`.

- **Bit-plane BFP vs baseline-BFP** — **smaller at every grid size**, −3.3 % at 8×8 and −3.5 % at 16×16, tending to `pe_bpl_bfp/pe_bfp = 0.963` (−3.7 %). It is the only variant whose crossover is at **N = 1**, and the reason is the shape of its overhead rather than the size of its saving: the per-tile saving is 197.09 µm² (`pe_bpl_bfp` 5148.90 vs `pe_bfp` 5345.99, −3.7 %) against an N term of just **149.90 µm²/column** — the extra area of [disp_array_b_bpl_bfp](../modules/disp_array_b_bpl_bfp.md) over `disp_array_b` (616.22 vs 466.33, **+32 %**). Crossover `N ≈ 149.90 / 197.09 ≈ 0.76`, i.e. already paid off at 2×2. Where the square variants add whole per-row/per-column *arrays*, the bit-plane variant only widens a dispatcher that already existed.

The parity is the payoff of the **per-DP8 7:2 reconstruction** ([ext_inject_sqr_bfp](../modules/ext_inject_sqr_bfp.md)): folding `{PE, −α, −β, C}` to `2·P` *before* the crossed tree lets the tree revert to baseline-BFP's narrow 2-row alignment, which is what brings `pe_sqr_bfp` (5204.93) **below** `pe_bfp` (5345.99) at all — the earlier fused 14:2-alignment build made the square-BFP PE larger than the plain BFP PE.

The BFP sideband itself costs ~40 % area on both axes (`Baseline-BFP/Baseline ≈ 1.40` at both sizes), dominated by the per-lane aligners in the PE.

## Cost and reproduction

Every run is at N = 2, so the whole sweep is cheap — the five component sets plus the five 2×2 grids take about 15 minutes together and need no special setup. Peak memory sits in the Slang frontend elaborating the top level and is modest at this size.

This is the reason the method changed. Elaboration cost scales as N² and blackboxing does not reduce it, because it only removes what is *below* the tile boundary: the old approach of synthesizing the full grids peaked at 6.7 GB for 8×8 and **25.9 GB for 16×16**, which does not fit a 30 GB machine and needed a swap file and serialized runs. The count model reproduces those totals exactly from the 2×2 data, so the large elaborations bought nothing and were dropped.

The one thing the assembly cannot capture is anything that is *not* a per-instance property — interconnect, clock tree and placement utilization at large N. Those come from P&R, not from synthesis at any grid size.
