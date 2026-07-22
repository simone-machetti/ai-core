# Synthesis Power — Baseline vs Square

VCD-annotated dynamic power comparison of [top_NxN](../architectures/top_NxN.md) (baseline) against [top_NxN_sqr](../architectures/top_NxN_sqr.md) (square), measured on the complete synthesized 2×2 grids and assembled from per-component unit power for 8×8 and 16×16.


## Purpose

[Synthesis Area](syn_area.md) established that the square variant trades an N² per-PE saving against an N per-row/column overhead, and that the crossover sits at 8×8. Area is not the deliverable on its own: the α/β generators run every cycle and the squarer's toggle profile is not the multiplier's, so the power crossover need not land where the area crossover does. This experiment measures where it actually lands.

## Method

Four passes. Passes A and B are those of [Synthesis Area](syn_area.md) at N=2 — each component synthesized once, then the grid synthesized with those netlists linked through `BLACKBOX_MODULES`, which is also what makes the per-instance power report possible. Pass C runs gate-level simulation of the resulting netlist to dump switching activity, and pass D annotates that activity onto the netlist in OpenSTA.

```
# pass C - gate-level simulation, dumps activity.vcd
make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=pwr_2x2 \
    NETLIST_DIR=top_2x2 TB=tb_top_NxN_pwr CLK_PERIOD_NS=10 VCD=1

# pass D - VCD-annotated power
make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=dpa_2x2 \
    NETLIST_DIR=top_2x2 VCD_DIR=pwr_2x2 TB=tb_top_NxN_pwr CLK_PERIOD_NS=10 \
    BLACKBOX_MODULES="pe ctrl disp_array_a disp_array_b icg"
```

Stimulus is `tb/tb_top_NxN_pwr.sv` / `tb/tb_top_NxN_sqr_pwr.sv` — 100 uniform-random operand sets per mode, streamed one per clock with every row and column enabled, single-shot only (`sel_acc` tied low, `acc` zero, no rectangle scaling), all 11 modes back to back with no reset and no idle between them so the VCD holds one continuous busy window. The two benches are byte-identical apart from the DUT, so the comparison is against the same stimulus. The netlist carries the tree operand isolation of [pe_array § Operand isolation](../modules/pe_array.md#operand-isolation-en_level).

`CLK_PERIOD_NS=10` (100 MHz) is the benches' clock, derived from the flow variable rather than hardcoded. Dumping starts after reset deassertion, so the reset transient is not charged to the average. The 100 vectors per mode match [Per-Mode Synthesis Power](syn_mode_pwr.md), so the two experiments are directly comparable — the figure here is the same workload merged into one VCD instead of measured mode by mode. The VCDs are 0.82 GB / 1.05 GB. Annotation is complete — 679 188 pins baseline, 885 044 square, **0 unannotated** — so every switching figure comes from the VCD rather than from a default toggle rate.

All commands are in [run_syn_pwr.sh](../../scripts/run_syn_pwr.sh). Numbers land in `doc/data/res_syn_pwr.xlsx` and `doc/charts/hist_syn_pwr.png`.

### Why 2×2 is measured and the larger grids are assembled

Unlike area, the larger grids are **not** measured. Verilator elaborates every instance of a gate-level netlist, so gate-level simulation memory scales as N² — 106 × N^1.99 MB, about 0.4 GB at 2×2 but 23.5 GB at 8×8 and some 370 GB at 16×16. Blackboxing does not help, because the netlist read by the simulator is already resolved.

So the 8×8 and 16×16 figures are assembled: each component's unit power is taken from the 2×2 per-instance report and multiplied by its instance count. This is exactly the assembly that [Synthesis Area](syn_area.md) validated against measurement at 8×8 and 16×16 — but validated for *area*, where a component's cost is instance-independent. Power is not: it depends on the activity a component sees, and in a larger grid the shared operands fan out further. What is reused is the per-instance activity, which the grid structure keeps identical — every PE sees an operand stream of the same statistics regardless of N. **Treat the 8×8 and 16×16 figures as projections, not measurements** — which is the opposite of [Synthesis Area](syn_area.md), where those two sizes are the measured ones.

## Instance counts

| Component                                               | Baseline | Square | ×count |
| ------------------------------------------------------- | -------- | ------ | ------ |
| [ctrl](../modules/ctrl.md) / `_sqr`                     | ✓        | ✓      | 1      |
| [const_sqr](../modules/const_sqr.md)                    |          | ✓      | 1      |
| [disp_array_a](../modules/disp_array_a.md) / `_sqr`     | ✓        | ✓      | N      |
| [disp_array_b](../modules/disp_array_b.md) / `_sqr`     | ✓        | ✓      | N      |
| [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md)  |          | ✓      | N      |
| [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md)    |          | ✓      | N      |
| [pe](../modules/pe.md) / [pe_sqr](../modules/pe_sqr.md) | ✓        | ✓      | N²     |
| [icg](../modules/icg.md) (per PE)                       | ✓        | ✓      | N²     |
| [icg](../modules/icg.md) (per row/column)               | ✓        | ✓      | 2N     |

The clock gates are split by position here, unlike in the area experiment: they are the same cell and the same area, but not the same power, since a per-PE gate and a per-row gate see different enable activity.

## Results

Per-component unit power from the 2×2 runs, mW:

| Baseline                                   | Power   | Square                                                 | Power   |
| ------------------------------------------ | ------- | ------------------------------------------------------ | ------- |
| [ctrl](../modules/ctrl.md)                 | 0.00123 | [ctrl_sqr](../modules/ctrl_sqr.md)                     | 0.00172 |
| [disp_array_a](../modules/disp_array_a.md) | 0.09425 | [const_sqr](../modules/const_sqr.md)                   | 0.00001 |
| [disp_array_b](../modules/disp_array_b.md) | 0.10500 | [disp_array_a_sqr](../modules/disp_array_a_sqr.md)     | 0.12600 |
| [pe](../modules/pe.md)                     | 0.63350 | [disp_array_b_sqr](../modules/disp_array_b_sqr.md)     | 0.10400 |
| [icg](../modules/icg.md) (per PE)          | 0.02080 | [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md) | 0.40100 |
| [icg](../modules/icg.md) (per row/col)     | 0.00591 | [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md)   | 0.36400 |
|                                            |         | [pe_sqr](../modules/pe_sqr.md)                         | 0.50900 |
|                                            |         | [icg](../modules/icg.md) (per PE)                      | 0.01970 |
|                                            |         | [icg](../modules/icg.md) (per row/col)                 | 0.01490 |

Grid totals, mW:

| Grid  | Baseline | Square  | Ratio  | Square vs baseline | Basis     |
| ----- | -------- | ------- | ------ | ------------------ | --------- |
| 2×2   | 3.041    | 4.167   | 1.3706 | +37.06 %           | measured  |
| 8×8   | 43.565   | 42.038  | 0.9650 | −3.50 %            | assembled |
| 16×16 | 170.879  | 151.747 | 0.8880 | −11.20 %           | assembled |

**The square costs 37.1 % more power at 2×2, saves 3.5 % at 8×8 and 11.2 % at 16×16.** Fitting the component counts gives

```
P_baseline(N) = 0.65430 N² + 0.21107 N + 0.00123   mW
P_square(N)   = 0.52870 N² + 1.02480 N + 0.00302   mW
```

so the per-tile saving is 0.12560 mW (−19.20 % per PE) against a 0.81373 mW cost per row+column. **The power crossover is at N = 6.48** — the square wins from 7×7 up — and the ratio tends to 0.8080.

The power crossover arrives **just before the area crossover**: N = 6.48 against N = 7.05, both rounding to a win from 7×7, and at 8×8 the power margin is more than twice the area margin (−3.50 % against −1.53 %). The reason is that the squarer's advantage is larger in switching than in cells — −19.20 % power per tile against −13.16 % area per tile. Replacing a multiplier array with a squarer array removes more toggling than it removes gates.

The α/β generators are the whole of the overhead — 0.7650 mW per row+column between them, against 0.0487 mW of extra dispatch and clock-gate power. They are also unconditionally active: they run every cycle regardless of the mode, which is why the 2×2 penalty is so large and why the crossover exists at all.

Split by category at 8×8: PE 41.88 → 33.84 mW, α/β 0 → 6.12 mW, dispatch 1.59 → 1.84 mW, clock gates 0.10 → 0.24 mW.

## Cost and reproduction

Per variant, baseline / square:

| Pass                             | Wall time      | Peak RAM       |
| -------------------------------- | -------------- | -------------- |
| B — 2×2 grid synthesis           | 25 / 40 s      | 0.56 / 0.78 GB |
| C — Verilator build              | 9.2 / 11.6 min | ~0.4 GB        |
| C — simulation only              | 18 / 16 s      | 0.18 / 0.23 GB |
| D — VCD-annotated power analysis | 70 / 85 s      | 1.07 GB        |

Pass C dominates, and essentially all of it is Verilator compiling the netlist, not simulating it: 1100 stimulus cycles run in **18 seconds**. The cost of gate-level power is a compile cost — it grows with netlist size, not with how much stimulus is driven, so a longer or richer stimulus is nearly free once the binary exists.

`read_vcd` is markedly **sublinear** in VCD size: going from 0.14 GB to 0.82 GB (5.9×) took the full power run from 30.8 s to 70.5 s (2.3×), and peak memory from 0.78 GB to 1.07 GB. Most of the cost is per-pin bookkeeping rather than per-transition, so stimulus length is cheap on this side too. Passes A and B are shared with [Synthesis Area](syn_area.md) and need not be rerun if that experiment has already run. Nothing here needs swap at 2×2.

Extending the measurement to 8×8 needs about 24 GB for pass C, which fits a 30 GB machine with the swap setup described in [Synthesis Area](syn_area.md), but the compile alone would take hours. 16×16 is out of reach for Verilator at gate level.
