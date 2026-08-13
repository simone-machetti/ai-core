# Per-Mode Synthesis Power — Baseline / Square / Baseline-BFP / Square-BFP / Bit-Plane-A BFP / Bit-Plane-B BFP

VCD-annotated dynamic power of the six PE-grid variants measured **once per operating mode** on the complete 2×2 grids and assembled per component for 8×8 and 16×16.

## Purpose

[Synthesis Power](syn_pwr.md) drove all 11 modes into a single VCD and reported one averaged figure per variant. That average hides an enormous per-mode spread: the square's 8×8 margin runs from **−22.4 % (mode 6) to +1.4 % (mode 1)**, and the square-BFP's from **−14.1 % (mode 6) to +4.8 % (mode 1)** — so a single number both understates the win and hides the modes where the square is a net loss at the target grid size. The bit-plane variant makes the point far more sharply still: its grid-average is a flat −0.3 %, but per mode it runs from **−11.2 % to +23.1 %**. This experiment measures each mode on its own.

## Method

As [Synthesis Power](syn_pwr.md) — per-component synthesis, blackbox-linked 2×2 grids, gate-level simulation, OpenSTA power with the resulting activity annotated — but pass C is run once per mode, 100 random operand sets in that mode alone. Five variants × 11 modes = **55 gate-level runs**, each reusing its variant's one compiled binary (`MODE_SEL` / `NUM_STREAM` are read from `+mode` / `+vectors` at run time), because the Verilator build takes ~10 min per variant while a simulation takes ~2 s — compiling per mode would turn the sweep into hours.

```
simv +mode=<m> +vectors=100          # one gate-level run per mode, per variant

make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp \
    OUT_DIR=top_2x2_sqr_bfp_m<m>_post_syn_dpa NETLIST_DIR=top_2x2_sqr_bfp_syn \
    VCD_DIR=top_2x2_sqr_bfp_m<m>_post_syn_sim TB=tb_top_NxN_sqr_bfp_pwr CLK_PERIOD_NS=10 \
    BLACKBOX_MODULES="pe_sqr_bfp ctrl_sqr …"
```

Clock is 100 MHz on all sides (derived from `CLK_PERIOD_NS`, so simulated and SDC clocks cannot drift); dumping starts after reset deassertion. Annotation is complete on every run (0 unannotated pins). Only 2×2 is measured — gate-level simulation memory grows as N² — so the 8×8 / 16×16 columns are assembled per component and are **projections, not measurements**.

All commands are in [run_syn_mode_pwr.sh](../../scripts/run_syn_mode_pwr.sh). Numbers land in `doc/data/res_syn_mode_pwr.xlsx` and `doc/charts/hist_syn_mode_pwr_{8x8,16x16}.png`. The charts are normalized to the baseline **averaged over the 11 modes** — one reference for the whole figure rather than one per mode, so the per-mode spread of the baseline itself stays readable (modes 5 and 6 sit near 0.6 while the rest cluster around 1.1). That reference coincides with the all-mode figure of [Synthesis Power](syn_pwr.md) to a fraction of a percent, so the two power charts share a unit.

## Results

Per-mode margin of each square variant against **its own baseline** (assembled totals; negative = the square wins):

| Mode | Square/Base 8×8 | Square/Base 16×16 | Sqr-BFP/Base-BFP 8×8 | Sqr-BFP/Base-BFP 16×16 | Bpl-A/Base-BFP 8×8 | Bpl-A/Base-BFP 16×16 | Bpl-B/Base-BFP 8×8 | Bpl-B/Base-BFP 16×16 | `sel_shift` |
| ---- | --------------- | ----------------- | -------------------- | ---------------------- | ------------------ | -------------------- | ------------------ | -------------------- | ----------- |
| 1    | **+1.4 %**      | −5.6 %            | **+4.8 %**           | **+0.8 %**             | **+23.1 %**        | **+23.0 %**          | −4.6 %             | −5.0 %               | `000`       |
| 2    | −10.9 %         | −17.9 %           | −4.6 %               | −8.5 %                 | −2.0 %             | −2.5 %               | −14.5 %            | −15.0 %              | `010`       |
| 3    | −4.0 %          | −11.4 %           | **+0.9 %**           | −3.0 %                 | **+1.2 %**         | **+0.8 %**           | −13.1 %            | −13.6 %              | `011`       |
| 5    | −12.8 %         | −18.9 %           | −5.6 %               | −8.4 %                 | **+22.8 %**        | **+22.9 %**          | −6.6 %             | −7.1 %               | `000`       |
| 6    | −22.4 %         | −28.5 %           | −14.1 %              | −17.1 %                | **+1.9 %**         | **+1.4 %**           | −16.8 %            | −17.6 %              | `010`       |
| 7    | −6.0 %          | −13.7 %           | **+0.9 %**           | −3.1 %                 | **+0.8 %**         | **+0.4 %**           | −13.8 %            | −14.3 %              | `011`       |
| 8    | −11.5 %         | −19.3 %           | −3.0 %               | −7.0 %                 | −11.2 %            | −11.8 %              | **−19.1 %**        | **−19.6 %**          | `111`       |
| 9    | −9.2 %          | −16.8 %           | −3.5 %               | −7.5 %                 | −11.2 %            | −11.7 %              | **−18.8 %**        | **−19.3 %**          | `111`       |
| 10   | −8.2 %          | −15.3 %           | −3.0 %               | −6.8 %                 | −1.7 %             | −2.2 %               | −14.2 %            | −14.7 %              | `010`       |
| 11   | −10.3 %         | −17.7 %           | −4.4 %               | −8.3 %                 | −3.7 %             | −4.2 %               | −16.2 %            | −16.7 %              | `010`       |
| 12   | −9.0 %          | −16.5 %           | −3.2 %               | −7.1 %                 | −11.1 %            | −11.6 %              | **−18.7 %**        | **−19.2 %**          | `111`       |
| mean | −8.8 %          | −16.1 %           | −2.7 %               | −6.5 %                 | +0.8 %             | +0.4 %               | **−14.2 %**        | **−14.7 %**          |             |

**Square vs baseline:** wins **10 of 11** at 8×8 (loses only mode 1) and **11 of 11** at 16×16. **Square-BFP vs baseline-BFP:** wins **8 of 11** at 8×8 (loses modes 1, 3, 7 — all narrowly) and **10 of 11** at 16×16 (loses only mode 1). **Bit-plane-A BFP vs baseline-BFP:** wins **6 of 11** at both sizes, and the spread is by far the widest — a 34-point range against the square's 24 and the square-BFP's 19. **Bit-plane-B BFP vs baseline-BFP:** wins **11 of 11** at both sizes, the only variant to sweep every mode, over a 14-point range (−4.6 % to −19.1 % at 8×8).

For the two square pairs the mean margins match the all-mode merged figures of [Synthesis Power](syn_pwr.md) to within 0.3 pp, cross-validating both experiments. The bit-plane pair does **not**: its unweighted per-mode mean is +0.8 % / +0.4 % against the merged run's −0.30 % / −0.75 %, a gap of ~1.1 pp. That is a consequence of the spread rather than a discrepancy — the merged VCD weights each mode by its actual toggle activity, and with a ±23 % range the unweighted mean and the activity-weighted one are simply different statistics. It is also a warning that no single number describes this variant. **Bit-plane B behaves like the square pairs rather than like bit-plane A**: its unweighted mean of −14.2 % / −14.7 % sits within 0.3 pp of the merged run's −14.5 % / −15.0 %, so for that variant a single number *is* usable.

### The bit-plane margin tracks `sel_shift`, not lane utilization

The `sel_shift` column above is `ctrl`'s per-mode tree shift enables (see [ctrl](../modules/ctrl.md)), and the correlation with the bit-plane margin is almost exact:

| `sel_shift` | shifts enabled | modes        | Bpl-A margin at 8×8 | Bpl-B margin at 8×8 |
| ----------- | -------------- | ------------ | ------------------- | ------------------- |
| `000`       | 0              | 1, 5         | **+23 %**           | −4.6 … −6.6 %       |
| `010`       | 1              | 2, 6, 10, 11 | −3.7 … +1.9 %       | −14.2 … −16.8 %     |
| `011`       | 2              | 3, 7         | +0.8 … +1.2 %       | −13.1 … −13.8 %     |
| `111`       | 3              | 8, 9, 12     | **−11 %**           | **−19 %**           |

Nothing else in the mode tables sorts the data this cleanly — in particular the lane-utilization measure that explains the *baseline* spread does not (modes 1 and 5 sit at opposite ends of it, 100 % and 50 %, yet give the same +23 %; modes 5 and 6 share a utilization but differ by 21 points).

A plausible mechanism, offered as a hypothesis rather than a measurement: with `sel_shift = 000` the two halves entering a tree node overlap completely in weight, so every bit of every row meets a full adder. The bit-plane DP8 hands up a **22-bit** carry-save row where Booth hands up 20, plus a guard bit at L0 and L1, and in the fully-overlapped case that extra width toggles at every level with nothing to offset it. With all three shifts on, the rows are spread apart in weight, much of each node passes through untouched, and the cheaper selection stage dominates. Confirming this would need a per-section power breakdown inside the PE, which this experiment does not produce.

### Where the bit-plane wins and loses, structurally

Per-tile saving, dispatcher cost per row+column, and the resulting crossover:

| Mode | save/tile [mW] | dispatch per row+col [mW] | crossover N | asymptote |
| ---- | -------------- | ------------------------- | ----------- | --------- |
| 1    | **−0.2060**    | 0.0750                    | never       | 1.2287    |
| 2    | +0.0303        | 0.0705                    | 2.33        | 0.9705    |
| 3    | −0.0035        | 0.0698                    | never       | 1.0034    |
| 5    | **−0.1292**    | 0.0505                    | never       | 1.2288    |
| 6    | −0.0052        | 0.0501                    | never       | 1.0091    |
| 7    | +0.0006        | 0.0710                    | 129.1       | 0.9994    |
| 8    | +0.1251        | 0.0680                    | **0.54**    | 0.8763    |
| 9    | +0.1276        | 0.0680                    | **0.53**    | 0.8769    |
| 10   | +0.0268        | 0.0714                    | 2.66        | 0.9737    |
| 11   | +0.0468        | 0.0705                    | 1.51        | 0.9531    |
| 12   | +0.1251        | 0.0677                    | **0.54**    | 0.8784    |

This is a qualitatively different picture from the square pairs. There, every mode has a positive per-tile saving and the question is only *when* the N term is amortized. Here **four modes (1, 3, 5, 6) have a negative per-tile saving** — the bit-plane PE is simply more expensive in them — so no grid size ever recovers them; mode 7 breaks even. The three `111` modes, conversely, cross over below N = 1: they win at every size including 2×2.

**Bit-plane B removes the pathology entirely.** All 11 modes have a **positive** per-tile saving, from +0.0438 mW (mode 5) to +0.2058 mW (mode 9), and the per-mode crossover is below N = 1 in every one of them (worst case N = 0.92 in mode 1). There is no mode it cannot win at any grid size. The `sel_shift` correlation survives — the no-shift modes 1 and 5 are still its weakest at −4.6 % and −6.6 %, the `111` modes still its strongest at ≈ −19 % — but halving the bit planes lowers the whole curve far enough that the weakest case is still a win rather than a +23 % penalty.

### Baseline power tracks lane utilization

Both baselines span a wide per-mode range explained by how many of the PE's MAC lanes the mode occupies. A lane is one 8×4 multiply, so a mode's lane count is its logical product count scaled by the lanes each product needs (a 16-bit A costs two lanes, an 8-bit B two nibbles). On that measure **modes 5 and 6 sit at 50 % and every other mode is at 100 %**, and the PE power follows — roughly 0.37 mW/PE for the two half-occupied modes against 0.62–0.71 mW for the rest. Counting logical products alone (`M·K·N`) is misleading here — it makes mode 8 look like a fraction of mode 1's work when both fill the array.

### Both terms scale with the mode; their ratio sets the crossover

The square's economics are an N² per-tile saving against an N per-row/column cost, and **both** vary by mode. Per pair (per-tile PE saving, α/β cost per row+column, the resulting crossover N, and the N→∞ asymptote):

**Square vs Baseline**

| Mode | save/tile [mW] | α/β per row+col [mW] | crossover N | asymptote |
| ---- | -------------- | -------------------- | ----------- | --------- |
| 1    | 0.0834         | 0.6900               | 8.93        | 0.8704    |
| 2    | 0.1878         | 0.7770               | 4.42        | 0.7489    |
| 3    | 0.1421         | 0.8370               | 6.24        | 0.8098    |
| 5    | 0.1011         | 0.3630               | 3.70        | 0.7465    |
| 6    | 0.1511         | 0.3835               | 2.56        | 0.6501    |
| 7    | 0.1603         | 0.8635               | 5.72        | 0.7835    |
| 8    | 0.2118         | 0.9005               | 4.50        | 0.7275    |
| 9    | 0.1928         | 0.8895               | 4.89        | 0.7542    |
| 10   | 0.1706         | 0.8020               | 5.00        | 0.7732    |
| 11   | 0.1894         | 0.8235               | 4.63        | 0.7470    |
| 12   | 0.1899         | 0.8895               | 4.96        | 0.7572    |

**Square-BFP vs Baseline-BFP** (smaller savings — the BFP PE is ~35 % busier — but cheaper, **tree-less** α/β generators)

| Mode | save/tile [mW] | α/β per row+col [mW] | crossover N | asymptote |
| ---- | -------------- | -------------------- | ----------- | --------- |
| 1    | 0.0299         | 0.5690               | 19.97       | 0.9668    |
| 2    | 0.1279         | 0.6030               | 4.93        | 0.8753    |
| 3    | 0.0702         | 0.6140               | 9.11        | 0.9301    |
| 5    | 0.0646         | 0.2630               | 3.89        | 0.8855    |
| 6    | 0.1159         | 0.2720               | 2.18        | 0.7966    |
| 7    | 0.0714         | 0.6185               | 9.06        | 0.9269    |
| 8    | 0.1134         | 0.6310               | 5.80        | 0.8878    |
| 9    | 0.1199         | 0.6310               | 5.48        | 0.8843    |
| 10   | 0.1101         | 0.6025               | 5.71        | 0.8921    |
| 11   | 0.1242         | 0.6035               | 5.10        | 0.8757    |
| 12   | 0.1154         | 0.6305               | 5.69        | 0.8878    |

The crossover ranges **N = 2.56 to 8.93** for the square and **N = 2.18 to 19.97** for the square-BFP. What decides it is the *ratio* of per-tile saving to per-row cost, not the absolute size of either — the α/β generators are not a fixed overhead, they see the same operands the PEs do, so in modes 5/6 they cost ~0.36 mW/row+col (square) / ~0.27 (square-BFP) against ~0.85 / ~0.62 elsewhere.

**Mode 1 is the outlier at both ends of both pairs** — the smallest per-tile saving (`pe → pe_sqr` is only −7 % there, against −32 % in mode 6) combined with a full-cost α/β. That pushes its crossover to N ≈ 8.9 (square) and N ≈ 20.0 (square-BFP), which is why it is the mode where each square loses at 8×8 (and, for square-BFP, still narrowly loses at 16×16). **Mode 6 is the opposite** — a large per-tile saving against the cheapest α/β — giving crossover N ≈ 2.2–2.6 and the biggest wins at every size.

## Consequences

The single-number answers from [Synthesis Power](syn_pwr.md) (square wins from 5×5; square-BFP from 6×6) are correct on average but not usable as a design guide.

- If the workload is mode-1 heavy, the square is the wrong choice at both 8×8 and 16×16; the square-BFP additionally loses modes 3 and 7 at 8×8. For the remaining modes both win.
- **Bit-plane A is the most workload-sensitive variant, and the only one with modes it can never win.** A workload dominated by modes 8/9/12 gets a consistent −11 % at any grid size; one dominated by modes 1 or 5 pays +23 % at any grid size. Because those are properties of the *PE*, not of the N overhead, they cannot be engineered away by growing the grid — only by attacking the tree in the no-shift case. Given that its area advantage (−3.3 %) is uniform across modes while its power result is not, bit-plane A reads as an area play with a workload-dependent power side effect.
- **Bit-plane B is the one variant that needs no workload caveat.** It wins every mode at every grid size, its worst mode (−4.6 %) still beats the *best* result either square pair achieves on average, and its per-mode mean matches its merged figure. Whatever the mode mix, the answer is between −5 % and −19 %.
- The α/β generators are worth attacking **selectively**. They are pure overhead in every mode but cost 2–3× more in the full modes than in modes 5/6, so clock-gating them when a mode does not need full-rate correction moves the crossover most where it currently sits worst. The square-BFP already halves this overhead structurally with its tree-less generators.

## Caveats

Everything from [Synthesis Power](syn_pwr.md) applies — hostile uniform-random stimulus, pre-layout (no interconnect or clock tree), unconstrained netlist. Two more: each run stays in one mode, so **mode-transition power is not captured** anywhere; and the mean row is an **unweighted** mean over modes, not a workload average — weighting by real mode usage would move it, and the spread is wide enough that the weighting matters more than the measurement precision.

## Cost

| Pass                           | Wall time |
| ------------------------------ | --------- |
| A + B — synthesis (5 variants) | ~15 min   |
| C — 5 Verilator builds         | ~50 min   |
| C — 55 gate-level simulations  | ~3 min    |
| D — 55 power runs              | ~31 min   |

Each `activity.vcd` is deleted once its power report exists; any one regenerates in ~2 s from the compiled binary.
