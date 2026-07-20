# Synthesis Area — Baseline vs Square

Cell-area comparison of [top_NxN](../architectures/top_NxN.md) (baseline) against [top_NxN_sqr](../architectures/top_NxN_sqr.md) (square) at 8×8 and 16×16, measured on the complete synthesized grids.

## Purpose

The square variant replaces each PE's multipliers with squarers, which should shrink the PE, but it pays for that with per-row and per-column α/β correction generators that the baseline does not have. The saving is an N² term and the overhead is an N term, so which design wins depends entirely on grid size. This experiment measures both at the two sizes of interest and reports the ratio; absolute µm² is not the deliverable.

## Method

Two passes. Pass A synthesizes each component once on its own. Pass B synthesizes the whole grid, linking those netlists through `BLACKBOX_MODULES` rather than re-elaborating every instance — so the run cost stops depending on how many PEs the grid has, and the netlist carries one shared module per component instead of one copy per instance. That is also the hierarchy a tiled place-and-route wants: the PE is the replicated tile, hardened once and placed N² times.

```
# pass A - one run per component, OUT_DIR must be the module name
make syn PROJECT=ai-core TOP_LEVEL=<module> OUT_DIR=<module>

# pass B - the complete grid
make syn PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_8x8 PARAMS="N=8" \
    BLACKBOX_MODULES="pe ctrl disp_array_a disp_array_b icg"
```

Library is `asap7sc7p5t` RVT TT — `dfflibmap` for flip-flops, the platform latch map for latches, `abc` for combinational logic. Pass B resolves each blackboxed module at `imp/<module>/output/netlist.v`, hence `OUT_DIR=<module>` in pass A. Only the grid size needs `-G` (`PARAMS="N=8"`); every component has a `localparam`-only interface. Every component's area is therefore its own pass-A figure; only the top-level glue is synthesized in grid context.

Interconnect, clock tree and placement utilization are out of scope and come later from P&R.

All commands are in [run_syn_area.sh](../../scripts/run_syn_area.sh). Numbers land in `doc/data/res_syn_area.xlsx` and `doc/charts/hist_syn_area.png`.

## Instance counts

| Component                                                       | Baseline | Square | ×count  |
| --------------------------------------------------------------- | -------- | ------ | ------- |
| [ctrl](../modules/ctrl.md) / [ctrl_sqr](../modules/ctrl_sqr.md) | ✓        | ✓      | 1       |
| [const_sqr](../modules/const_sqr.md)                            |          | ✓      | 1       |
| [disp_array_a](../modules/disp_array_a.md) / `_sqr`             | ✓        | ✓      | N       |
| [disp_array_b](../modules/disp_array_b.md) / `_sqr`             | ✓        | ✓      | N       |
| [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md)          |          | ✓      | N       |
| [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md)            |          | ✓      | N       |
| [pe](../modules/pe.md) / [pe_sqr](../modules/pe_sqr.md)         | ✓        | ✓      | N²      |
| [icg](../modules/icg.md)                                        | ✓        | ✓      | N² + 2N |

The clock-gate count is identical on both sides — one per PE, one per row, one per column: 80 at 8×8, 288 at 16×16. Since [icg](../modules/icg.md) now instantiates the ASAP7 `ICGx1` cell it carries a real 0.26244 µm², and it is included in every figure below.

Top-level glue has no component home: the `sel_acc` pipeline (2 flops baseline, 46 with the const pipeline on the square side) plus the wiring that fans the shared operands and controls out to the grid. It is the only term measured rather than linked.

## Results

Per-component unit areas from pass A, µm²:

| Baseline                                   | Area     | Square                                                 | Area     |
| ------------------------------------------ | -------- | ------------------------------------------------------ | -------- |
| [ctrl](../modules/ctrl.md)                 | 9.229    | [ctrl_sqr](../modules/ctrl_sqr.md)                     | 9.462    |
| [disp_array_a](../modules/disp_array_a.md) | 348.681  | [const_sqr](../modules/const_sqr.md)                   | 4.068    |
| [disp_array_b](../modules/disp_array_b.md) | 502.485  | [disp_array_a_sqr](../modules/disp_array_a_sqr.md)     | 394.783  |
| [pe](../modules/pe.md)                     | 3758.943 | [disp_array_b_sqr](../modules/disp_array_b_sqr.md)     | 349.599  |
| [icg](../modules/icg.md)                   | 0.262    | [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md) | 1890.268 |
|                                            |          | [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md)   | 1699.809 |
|                                            |          | [pe_sqr](../modules/pe_sqr.md)                         | 3264.185 |

Grid totals, µm²:

| Grid  | Baseline  | Square    | Ratio   | Square vs baseline |
| ----- | --------- | --------- | ------- | ------------------ |
| 8×8   | 247422.06 | 243646.82 | 0.98474 | −1.53 %            |
| 16×16 | 976030.97 | 905128.59 | 0.92736 | −7.26 %            |

**The square is 1.5 % smaller at 8×8 and 7.3 % smaller at 16×16**, and the gap widens with N. The saving is per-PE — 494.76 µm² per tile, an N² term — while the cost is the α/β generators at 3483.29 µm² per row+column, an N term. Doubling N doubles the saving relative to the overhead, so the ratio walks from 1.2991 at 2×2 down toward its 0.8684 asymptote. 8×8 is the crossover: the first power-of-two grid where the square wins at all.

## Cost and reproduction

| Grid  | Peak RAM | Wall time |
| ----- | -------- | --------- |
| 8×8   | 6.7 GB   | 3.1 min   |
| 16×16 | 25.9 GB  | 11.8 min  |

Peak memory scales as N² and sits in the Slang frontend elaborating the top level (N² PE cells, plus `acc_i` / `out_q_o` at 40 960 bits each when N=16). Blackboxing does not reduce it, because it only removes what is below the tile boundary.

25.9 GB does not fit a 30 GB machine, so the 16×16 runs need swap. The peak is transient — once elaboration finishes the design collapses to N² cells plus glue — so the paging cost is small (3.6 GB paged at peak, on NVMe).

```bash
sudo fallocate -l 32G /swapfile2
sudo chmod 600 /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2
sudo sysctl vm.swappiness=10   # prefer dropping page cache over swapping the heap
```

Afterwards — not while a run is in flight, `swapoff` has to page everything back in:

```bash
sudo swapoff /swapfile2
sudo rm /swapfile2
sudo sysctl vm.swappiness=60
```

Run the two 16×16 grids one at a time; two concurrent peaks do not fit even with swap.
