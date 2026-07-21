# Per-Mode Synthesis Power — Baseline vs Square

VCD-annotated dynamic power of [top_NxN](../architectures/top_NxN.md) (baseline) against [top_NxN_sqr](../architectures/top_NxN_sqr.md) (square), measured **once per operating mode** on the complete 2×2 grids and assembled per component for 8×8 and 16×16.

## Purpose

[Synthesis Power](syn_pwr.md) drove all 11 modes into a single VCD and reported one averaged figure. That average is the wrong summary if the modes differ, and this experiment shows they differ enormously: the square's margin at 8×8 ranges from **−18.4 % to +6.5 %** across modes, so a single number both understates the win and hides a mode where the square is a net loss at the target grid size.

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

Clock is 100 MHz on both sides, and the benches now derive their period from the flow's `CLK_PERIOD_NS` instead of hardcoding it, so the simulated clock and the SDC clock cannot drift apart. Dumping starts after reset deassertion, so the reset transient is not charged to the per-mode average. Annotation is complete on every run — 667 361 pins baseline, 858 237 square, 0 unannotated.

All commands are in [run_syn_mode_pwr.sh](../../scripts/run_syn_mode_pwr.sh). Numbers land in `doc/data/res_syn_mode_pwr.xlsx` and `doc/charts/hist_syn_mode_pwr_{8x8,16x16}.png`.

Only 2×2 is measured, for the reason given in [Synthesis Power](syn_pwr.md): gate-level simulation memory grows as N². The 8×8 and 16×16 columns are assembled from per-component unit power and are **projections, not measurements**.

## Results

Measured 2×2 and assembled grids, mW:

| Mode | 2×2 bas | 2×2 sqr | 8×8 bas | 8×8 sqr | 8×8      | 16×16 bas | 16×16 sqr | 16×16    |
| ---- | ------- | ------- | ------- | ------- | -------- | --------- | --------- | -------- |
| 1    | 2.9235  | 4.1926  | 41.659  | 44.352  | +6.47 %  | 163.227   | 162.265   | −0.59 %  |
| 2    | 3.2885  | 4.1826  | 47.509  | 43.145  | −9.18 %  | 186.639   | 156.746   | −16.02 % |
| 3    | 3.2188  | 4.4543  | 46.989  | 46.461  | −1.12 %  | 184.960   | 169.329   | −8.45 %  |
| 5    | 1.8610  | 2.2627  | 24.879  | 22.878  | −8.05 %  | 96.260    | 82.643    | −14.15 % |
| 6    | 1.9854  | 2.2339  | 26.852  | 21.921  | −18.36 % | 104.141   | 78.488    | −24.63 % |
| 7    | 3.1781  | 4.3238  | 45.722  | 43.815  | −4.17 %  | 179.481   | 158.371   | −11.76 % |
| 8    | 3.3014  | 4.2991  | 47.715  | 42.731  | −10.45 % | 187.467   | 153.580   | −18.08 % |
| 9    | 3.3534  | 4.4271  | 48.547  | 44.731  | −7.86 %  | 190.795   | 161.548   | −15.33 % |
| 10   | 3.3129  | 4.3216  | 47.858  | 44.682  | −6.63 %  | 188.008   | 162.443   | −13.60 % |
| 11   | 3.2218  | 4.1787  | 46.377  | 42.346  | −8.69 %  | 182.071   | 153.067   | −15.93 % |
| 12   | 3.2935  | 4.3684  | 48.212  | 44.544  | −7.61 %  | 189.869   | 161.302   | −15.05 % |
| mean | 3.0655  | 3.9678  | 43.865  | 40.109  | −6.88 %  | 168.629   | 145.489   | −13.96 % |

**At 8×8 the square wins in 10 of 11 modes and loses in mode 1.** At 16×16 it wins in all 11, but mode 1 only breaks even. The mean margin is −6.88 % at 8×8 and −13.96 % at 16×16 — both **better** than the all-mode figures of −3.59 % and −10.89 % in [Synthesis Power](syn_pwr.md), because the single averaged VCD is dominated by the high-power modes.

### Baseline power does not track arithmetic work

The baseline alone spans 1.86 to 3.35 mW at 2×2, a **1.80× spread**, and it is not explained by how much computation a mode performs. Mode 1 does 128 MACs (M·K·N) for 2.92 mW; mode 8 does 16 MACs — an eighth of the work — for 3.30 mW, *more* power. The two low modes are 5 and 6, the only two with K = 32. Power is set by how much the datapath toggles under a given operand packing, not by the useful work extracted from it.

### Both terms scale with the mode; their ratio sets the crossover

The square's economics are an N² per-tile saving against an N per-row/column cost, and **both** vary by mode:

| Mode | saving per tile [mW] | α/β per row+col [mW] | crossover N | asymptote |
| ---- | -------------------- | -------------------- | ----------- | --------- |
| 1    | 0.0496               | 0.7335               | 14.79       | 0.9206    |
| 2    | 0.1654               | 0.7773               | 4.70        | 0.7690    |
| 3    | 0.1139               | 0.8446               | 7.42        | 0.8398    |
| 5    | 0.0751               | 0.3505               | 4.67        | 0.7933    |
| 6    | 0.1234               | 0.3702               | 3.01        | 0.6870    |
| 7    | 0.1351               | 0.8422               | 6.24        | 0.8036    |
| 8    | 0.1869               | 0.8715               | 4.67        | 0.7401    |
| 9    | 0.1689               | 0.8735               | 5.18        | 0.7693    |
| 10   | 0.1501               | 0.8037               | 5.36        | 0.7918    |
| 11   | 0.1636               | 0.8048               | 4.92        | 0.7655    |
| 12   | 0.1659               | 0.8681               | 5.24        | 0.7728    |

**The crossover ranges from N = 3.01 to N = 14.79.** The α/β generators are not a fixed overhead: they see the same operands the PEs do, so in modes 5 and 6 they cost 0.35–0.37 mW per row+column against 0.73–0.87 mW elsewhere. What decides the crossover is the *ratio* of per-tile saving to per-row cost, not the absolute size of either.

Mode 1 is the outlier at both ends — the smallest per-tile saving (0.0496 mW, because `pe → pe_sqr` is only −8.0 % there against −21.6 % in mode 5) combined with a full-cost α/β. That pushes its crossover out to N ≈ 14.8, which is why it is the one mode where the square loses at 8×8 and barely breaks even at 16×16.

Mode 6 is the opposite: a large per-tile saving against the cheapest α/β of any mode, giving a crossover at N = 3.01 and −18.4 % already at 8×8.

## Consequences

The single-number answer from [Synthesis Power](syn_pwr.md) — square wins from 7×7, −3.6 % at 8×8 — is not wrong on average but is not usable as a design guide. Two things follow.

If the workload is known to be mode-1 heavy, the square is the wrong choice at 8×8 and roughly neutral at 16×16. For every other mode it wins at 8×8, most by 4–18 %.

And the α/β generators are worth attacking selectively rather than uniformly. They are pure overhead in every mode, but they cost 0.73–0.87 mW per row+column in nine of the eleven modes and only ~0.36 mW in modes 5 and 6. Clock-gating them when a mode does not need full-rate correction would move the crossover most where it currently sits worst.

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
