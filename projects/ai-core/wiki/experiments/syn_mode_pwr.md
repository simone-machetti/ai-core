# Per-Mode Synthesis Power — Baseline vs Square

VCD-annotated dynamic power of [top_NxN](../architectures/top_NxN.md) (baseline) against [top_NxN_sqr](../architectures/top_NxN_sqr.md) (square), measured **once per operating mode** on the complete 2×2 grids and assembled per component for 8×8 and 16×16.


## Purpose

[Synthesis Power](syn_pwr.md) drove all 11 modes into a single VCD and reported one averaged figure. That average is the wrong summary if the modes differ, and this experiment shows they differ enormously: the square's margin at 8×8 ranges from **−16.9 % (mode 6) to +8.0 % (mode 1)** across modes, so a single number both understates the win and hides the two modes where the square is a net loss at the target grid size.

## Method

As [Synthesis Power](syn_pwr.md) — per-component synthesis, blackbox-linked 2×2 grids, gate-level simulation, OpenSTA power with the resulting activity annotated — but pass C is run once per mode, with 100 random operand sets in that mode alone rather than 10 in each of 11.

```
# one gate-level run per mode, reusing one compiled binary
simv +mode=<m> +vectors=100

make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=dpa_mode_2x2_m<m> \
    NETLIST_DIR=top_2x2 VCD_DIR=pwr_mode_2x2_m<m> TB=tb_top_NxN_pwr CLK_PERIOD_NS=10 \
    BLACKBOX_MODULES="pe ctrl disp_array_a disp_array_b icg"
```

`MODE_SEL` and `NUM_STREAM` are read from `+mode` / `+vectors` at run time, so all 22 runs reuse two compiled binaries. This is not a convenience — the Verilator build takes ~10 min per variant while the simulation itself takes ~2 s, so compiling per mode would turn a 35 min sweep into a 4 h one.

Clock is 100 MHz on both sides, and the benches now derive their period from the flow's `CLK_PERIOD_NS` instead of hardcoding it, so the simulated clock and the SDC clock cannot drift apart. Dumping starts after reset deassertion, so the reset transient is not charged to the per-mode average. Annotation is complete on every run — 679 188 pins baseline, 885 044 square, 0 unannotated. The netlist carries the tree operand isolation of [pe_array § Operand isolation](../modules/pe_array.md#operand-isolation-en_level).

All commands are in [run_syn_mode_pwr.sh](../../scripts/run_syn_mode_pwr.sh). Numbers land in `doc/data/res_syn_mode_pwr.xlsx` and `doc/charts/hist_syn_mode_pwr_{8x8,16x16}.png`.

Only 2×2 is measured, for the reason given in [Synthesis Power](syn_pwr.md): gate-level simulation memory grows as N². The 8×8 and 16×16 columns are assembled from per-component unit power and are **projections, not measurements**.

## Results

Measured 2×2 and assembled grids, mW:

| Mode | 2×2 bas | 2×2 sqr | 8×8 bas | 8×8 sqr | 8×8      | 16×16 bas | 16×16 sqr | 16×16    |
| ---- | ------- | ------- | ------- | ------- | -------- | --------- | --------- | -------- |
| 1    | 2.7973  | 4.1126  | 39.666  | 42.844  | +8.01 %  | 155.273   | 156.081   | +0.52 %  |
| 2    | 3.2136  | 4.2929  | 46.321  | 43.634  | −5.80 %  | 181.894   | 157.851   | −13.22 % |
| 3    | 3.1598  | 4.5485  | 46.057  | 46.837  | +1.70 %  | 181.238   | 170.081   | −6.16 %  |
| 5    | 1.8619  | 2.3246  | 24.906  | 23.352  | −6.24 %  | 96.377    | 84.199    | −12.64 % |
| 6    | 1.9965  | 2.2969  | 27.040  | 22.460  | −16.94 % | 104.900   | 80.334    | −23.42 % |
| 7    | 3.1853  | 4.5481  | 45.846  | 45.623  | −0.49 %  | 179.985   | 164.420   | −8.65 %  |
| 8    | 3.3289  | 4.5675  | 48.161  | 44.991  | −6.58 %  | 189.254   | 161.268   | −14.79 % |
| 9    | 3.3579  | 4.6484  | 48.625  | 46.551  | −4.26 %  | 191.110   | 167.684   | −12.26 % |
| 10   | 3.2319  | 4.4299  | 46.573  | 45.211  | −2.93 %  | 182.879   | 163.755   | −10.46 % |
| 11   | 3.2188  | 4.3871  | 46.352  | 43.971  | −5.14 %  | 181.990   | 158.428   | −12.95 % |
| 12   | 3.2978  | 4.5905  | 48.288  | 46.367  | −3.98 %  | 190.182   | 167.444   | −11.96 % |
| mean | 2.9681  | 4.0679  | 42.530  | 41.077  | −3.42 %  | 166.826   | 148.322   | −11.09 % |

**At 8×8 the square wins in 9 of 11 modes and loses in modes 1 and 3.** At 16×16 it wins in 10 of 11, losing only mode 1 (+0.52 %). The mean margin is −3.42 % at 8×8 and −11.09 % at 16×16, closely matching the all-mode figures of −3.50 % and −11.20 % in [Synthesis Power](syn_pwr.md) — with the tree operand isolation in the netlist, the per-mode detail and the merged summary now agree.

### Baseline power tracks lane utilization

The baseline spans 1.86 to 3.35 mW at 2×2, a **1.80× spread**, and it is explained by how many of the PE's 128 MAC lanes the mode occupies. A lane is one 8×4 multiply, so a mode's lane count is its logical product count scaled by the lanes each product needs — a 16-bit A costs two lanes, an 8-bit B costs two nibbles. On that measure **modes 5 and 6 sit at 50 % and every other mode is at 100 %**, and the power follows directly: 0.34–0.38 mW per PE for the two half-occupied modes against 0.57–0.71 mW for the rest, almost exactly 2×.

Counting logical products alone (M·K·N) is misleading here — it makes mode 8 look like an eighth of mode 1's work when both fill the array — and the remaining spread among the 100 % modes comes from operand packing and tap level, not from occupancy.

### Both terms scale with the mode; their ratio sets the crossover

The square's economics are an N² per-tile saving against an N per-row/column cost, and **both** vary by mode:

| Mode | saving per tile [mW] | α/β per row+col [mW] | crossover N | asymptote |
| ---- | -------------------- | -------------------- | ----------- | --------- |
| 1    | 0.0433               | 0.7441               | 17.16       | 0.9269    |
| 2    | 0.1458               | 0.8308               | 5.70        | 0.7908    |
| 3    | 0.0993               | 0.8922               | 8.98        | 0.8573    |
| 5    | 0.0709               | 0.3724               | 5.26        | 0.8053    |
| 6    | 0.1204               | 0.3901               | 3.25        | 0.6969    |
| 7    | 0.1181               | 0.9167               | 7.76        | 0.8288    |
| 8    | 0.1691               | 0.9564               | 5.66        | 0.7671    |
| 9    | 0.1506               | 0.9454               | 6.28        | 0.7946    |
| 10   | 0.1281               | 0.8543               | 6.67        | 0.8173    |
| 11   | 0.1469               | 0.8769               | 5.97        | 0.7895    |
| 12   | 0.1476               | 0.9404               | 6.37        | 0.7982    |

**The crossover ranges from N = 3.25 to N = 17.16.** The α/β generators are not a fixed overhead: they see the same operands the PEs do, so in modes 5 and 6 they cost 0.37–0.39 mW per row+column against 0.74–0.96 mW elsewhere. What decides the crossover is the *ratio* of per-tile saving to per-row cost, not the absolute size of either.

Mode 1 is the outlier at both ends — the smallest per-tile saving (0.0433 mW, because `pe → pe_sqr` is only −7.4 % there against −31.7 % in mode 6) combined with a full-cost α/β. That pushes its crossover out to N ≈ 17.2, which is why it is the one mode where the square loses at both 8×8 and 16×16.

Mode 6 is the opposite: a large per-tile saving against the cheapest α/β of any mode, giving a crossover at N = 3.25 and −16.9 % already at 8×8.

## Consequences

The single-number answer from [Synthesis Power](syn_pwr.md) — square wins from 7×7, −3.5 % at 8×8 — is not wrong on average but is not usable as a design guide. Two things follow.

If the workload is known to be mode-1 heavy, the square is the wrong choice at both 8×8 and 16×16 (mode 3 is also a small loss at 8×8). For the other nine modes it wins at 8×8, by 0.5–17 %.

And the α/β generators are worth attacking selectively rather than uniformly. They are pure overhead in every mode, but they cost 0.74–0.96 mW per row+column in nine of the eleven modes and only ~0.38 mW in modes 5 and 6. Clock-gating them when a mode does not need full-rate correction would move the crossover most where it currently sits worst.

## Caveats

Everything from [Synthesis Power](syn_pwr.md) applies — hostile uniform-random stimulus, pre-layout so no interconnect or clock tree, unconstrained netlist. Two more are specific to this experiment.

Each run stays in one mode for its whole window, so mode-transition power is not captured anywhere. A real workload switching modes will pay transitions that neither this experiment nor [Synthesis Power](syn_pwr.md) measures.

The mean row is an unweighted mean over modes, which is not a workload average. Weighting by actual mode usage would move it, and the spread is wide enough that the weighting matters more than the measurement precision.

## Cost

| Pass                          | Wall time   |
| ----------------------------- | ----------- |
| A + B — synthesis             | ~6 min      |
| C — 2 Verilator builds        | ~15 min     |
| C — 22 gate-level simulations | ~1 min      |
| D — 22 power runs             | ~11 min     |
| **total**                     | **~33 min** |

Each `activity.vcd` is deleted once its power report exists; keeping all 22 would cost ~3 GB, and any one regenerates in ~2 s from the compiled binary. The 22 report directories total ~1 GB.
