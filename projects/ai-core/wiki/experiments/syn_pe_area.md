# Intra-PE Area — Baseline / Square / Baseline-BFP / Square-BFP

Cell-area breakdown *inside* one processing element for the four variants — [pe](../modules/pe.md), [pe_sqr](../modules/pe_sqr.md), [pe_bfp](../modules/pe_bfp.md) and [pe_sqr_bfp](../modules/pe_sqr_bfp.md) — split into the DP8 array, the compression tree and the accumulator.

## Purpose

[Synthesis Area](syn_area.md) measures whole components and answers what a grid costs. It does not say **where** inside the PE the square identity wins and loses, and that is the interesting part: the squarer is dramatically cheaper than the multiplier at the arithmetic core, but the reconstruction `½(PE − α − β + C)` has to be paid somewhere. This experiment opens the PE up and shows where it lands.

Two scopes are reported. **DP level** is the array of 16 dot-product cores alone — the arithmetic, with no reduction tree and no accumulator. **PE level** is the complete tile, split into DP8 array / compression tree / accumulator / glue.

## Method

Pass A synthesizes the two dot-product cores standalone, as an independent cross-check on the in-context numbers. Pass B synthesizes each PE with the boundaries of its tree, its accumulator and its DP core preserved through `KEEP_MODULES`, so `stat -hierarchy` reports one chip area per preserved module:

```
# pass A - standalone dot-product cores
make syn PROJECT=ai-core TOP_LEVEL=dp_8     OUT_DIR=dp_8_syn
make syn PROJECT=ai-core TOP_LEVEL=dp_8_sqr OUT_DIR=dp_8_sqr_syn

# pass B - PEs with the internal module boundaries preserved
make syn PROJECT=ai-core TOP_LEVEL=pe_sqr_bfp OUT_DIR=pe_sqr_bfp_hier_syn \
    KEEP_MODULES="pe_array_sqr_bfp acc_array_sqr_bfp dp_8_sqr ext_inject_sqr_bfp"
```

Library is `asap7sc7p5t` RVT TT at the default `CLK_PERIOD_NS`, matching [Synthesis Area](syn_area.md) so the figures are comparable with the component areas measured there. The sections are then

| Section | Derivation |
| ------- | ----------- |
| DP8 array | sum of the 16 `dp_8` / `dp_8_sqr` instances |
| Compression tree | `pe_array*` minus those cores (square-BFP includes [ext_inject_sqr_bfp](../modules/ext_inject_sqr_bfp.md)) |
| Accumulator | `acc_array*` |
| PE glue | `pe*` minus `pe_array*` minus `acc_array*` — the `en_i` operand mask and the two `acc` pipeline register banks |

All commands are in [run_syn_pe_area.sh](../../scripts/run_syn_pe_area.sh). Numbers land in `doc/data/res_syn_pe_area.xlsx` and `doc/charts/hist_syn_dp_area.png` / `hist_syn_pe_area.png`; both charts are normalized, so they carry ratios rather than absolute µm².

**`KEEP_MODULES` uniquifies each instance**, so the 16 DP8s do not all come out at the same area — the baseline's are 15 × 190.808 µm² plus one at 197.603, the BFP's span 192.412–198.040. The sections above are sums over the instances, not one figure multiplied by 16.

## Results — DP level

Standalone cores and the same cores in context, µm²:

| Core       | Standalone | In-PE (per instance) | In-PE (×16) |
| ---------- | ---------- | -------------------- | ----------- |
| `dp_8`     | 202.414    | 191.233              | 3059.730    |
| `dp_8_sqr` | 129.427    | 118.288              | 1892.601    |

| Variant      | DP8 array [µm²] | Normalized | vs own baseline |
| ------------ | --------------- | ---------- | --------------- |
| Baseline     | 3059.730        | 1.000      | —               |
| Square       | 1892.601        | 0.619      | **−38.1 %**     |
| Baseline-BFP | 3091.572        | 1.010      | —               |
| Square-BFP   | 1892.601        | 0.619      | **−38.8 %**     |

Two readings:

- **The squarer is ~38 % smaller than the multiplier** at the arithmetic core. Standalone the ratio is −36.1 %; both cores shrink 5–9 % once placed inside the PE, but the ratio barely moves, so the in-context figure is not an artefact of boundary optimization.
- **BFP costs nothing here.** The BFP variants reuse the integer core unchanged, so their bars land on their integer counterparts (the 1.010 is instance-level uniquification, not a design difference). The entire BFP overhead is downstream, in the tree and the accumulator.

## Results — PE level

Hierarchical synthesis, µm², with the flat total for reference:

| Variant      | DP8 array | CPR tree | ACC array | PE glue | Hier. total | Flat total | Hier/flat |
| ------------ | --------- | -------- | --------- | ------- | ----------- | ---------- | --------- |
| Baseline     | 3059.730  | 704.651  | 331.578   | 269.672 | 4365.631    | 3816.519   | +14.4 %   |
| Square       | 1892.601  | 694.183  | 796.491   | 405.091 | 3788.365    | 3320.303   | +14.1 %   |
| Baseline-BFP | 3091.572  | 1698.322 | 861.036   | 333.824 | 5984.755    | 5345.990   | +11.9 %   |
| Square-BFP   | 1892.601  | 2747.936 | 848.848   | 434.601 | 5923.985    | 5204.929   | +13.8 %   |

Measured shares scaled to the flat totals, normalized to the baseline PE — this is what the chart plots:

| Variant      | DP8 array | CPR tree | ACC array | PE glue | Total | vs own baseline |
| ------------ | --------- | -------- | --------- | ------- | ----- | --------------- |
| Baseline     | 0.701     | 0.161    | 0.076     | 0.062   | 1.000 | —               |
| Square       | 0.435     | 0.159    | 0.183     | 0.093   | 0.870 | **−13.0 %**     |
| Baseline-BFP | 0.724     | 0.398    | 0.202     | 0.078   | 1.401 | —               |
| Square-BFP   | 0.436     | 0.633    | 0.195     | 0.100   | 1.364 | **−2.6 %**      |

- **The −38 % core saving becomes −13 % at PE level.** The squarer's reconstruction moves work into the accumulator: [acc_array_sqr](../modules/acc_array_sqr.md) is **2.4× larger** than [acc_array](../modules/acc_array.md) (0.076 → 0.183 of the baseline PE), because the all-additive resolve carries a triple tap mux, a wider CPR and the `½`.
- **Inside BFP the dilution is stronger**, leaving −2.6 %. There the reconstruction has to happen at a common exponent scale, so it loads the *tree* instead (0.398 → 0.633) — that section is where [ext_inject_sqr_bfp](../modules/ext_inject_sqr_bfp.md) lives, 0.223 of the baseline PE on its own.
- **The BFP sideband inflates the PE ~40 %** (1.401), almost all of it in the tree (per-lane aligners) and the accumulator (in-loop alignment) — the DP8 array is untouched, as the DP-level result already showed.

These two net figures, **−13.0 %** and **−2.6 %**, are the asymptotes of [Grid Scaling](syn_scaling.md): they are what each square variant achieves once the α/β overhead is amortized away.

## Caveats

Preserving a module boundary blocks cross-boundary optimization, so the hierarchical total runs **12–14 % above** the flat PE area used by every other experiment. The composition is measured, but the totals are not directly comparable with the flat figures — which is why the normalized table scales each variant's shares to its flat total. Quote the two separately and never substitute one for the other.

Everything else from [Synthesis Area](syn_area.md) applies: `asap7sc7p5t` RVT TT, pre-layout, interconnect and clock tree out of scope.
