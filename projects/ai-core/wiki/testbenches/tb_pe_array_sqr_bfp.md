# PE Array (Square-BFP) Testbench

## Purpose

`tb_pe_array_sqr_bfp` verifies [pe_array_sqr_bfp](../modules/pe_array_sqr_bfp.md) driven through the real square dispatchers [disp_array_a_sqr](../modules/disp_array_a_sqr.md) + [disp_array_b_sqr](../modules/disp_array_b_sqr.md) and the square BFP exponent dispatchers [disp_array_exp_a_sqr_bfp](../modules/disp_array_exp_a_sqr_bfp.md) + [disp_array_exp_b_sqr_bfp](../modules/disp_array_exp_b_sqr_bfp.md). This gate verifies the **crossed tree over the reconstructed leaves** — the [ext_inject_sqr_bfp](../modules/ext_inject_sqr_bfp.md) 7:2 combine, the block negate, the exponent max-tree, and the taps.

The α/β generators and [const_sqr_bfp](../modules/const_sqr_bfp.md) are earlier gates, so the tb computes the `−α` / `−β` carry-save and `const_dp8_i` **itself** from the *dispatched* (centered) operands and drives the DUT's α/β/const ports, using the exact square identity `PE_j − α_j − β_j = 2·P_j`. A small random per-DP8 `K` is added to `const` (and to the golden leaf) to exercise the constant path at arbitrary magnitude.

## Parameters

| Parameter  | Default | Description                                   |
| ---------- | ------- | --------------------------------------------- |
| `NUM_RAND` | `300`   | Random operand vectors per mode **per pass**. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_sqr_bfp
```

## What it checks

| Pass                       | Check                                                                                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A — equal exponents        | every read-level tap resolves **bit-exact** to the ideal reduction (`2·A·B`); every tap exponent equals the subtree max.                                      |
| B — distinct BFP exponents | tap exponents still exact; each read-level node value sits inside the truncation window `[ideal − allow, ideal]` (the L0 window widened to the 7-row bundle). |

Any mismatch is **fatal**.

## How it checks

### Control vectors

The centering / idle-zero / negate / shift LUTs are the square set (`IS_SIGNED_A/B`, `ZERO_I`, `NEG_I`, `SEL_SHIFT`, `TAP_LEVEL`) shared with [tb_pe_array_sqr](./tb_pe_array_sqr.md) — including the mode-5 `is_signed_b` idle fix. `NEG_I` is the 6-bit block negate mapped onto the negatable DP8s.

### The golden

Each DP8 leaf resolves to `±2·P_j` (negated blocks → `−2·P_j` via the PE [comp_n](../modules/comp_n.md) plus the `+2` in `const`). The golden is the tb's **own** reduction of those leaves through the crossed tree (radix shifts gated by `SEL_SHIFT`, exponent alignment), so the check exercises the L0 combine, the block negate, the max-tree and the taps as one path. **Pass A** (equal exponents) demands a bit-exact tap; **Pass B** (distinct legal BFP exponents) allows the per-tap truncation window, widened at L0 to the 7-row `{PE, −α, −β, C}` bundle.

### Drive/sample timing

The dispatchers and `pe_array_sqr_bfp`'s L0 both register, so each vector is clocked through before the taps are sampled. Operands are corner-biased to stress carry-save sign-consistency in the combine — the same stress that catches the front-end's `EXT`-guard bug (a one-`2¹⁸` miss on the R16 modes).

Source: [tb_pe_array_sqr_bfp.sv](../../tb/tb_pe_array_sqr_bfp.sv) — DUT: [pe_array_sqr_bfp](../modules/pe_array_sqr_bfp.md) (through [disp_array_a_sqr](../modules/disp_array_a_sqr.md) + [disp_array_b_sqr](../modules/disp_array_b_sqr.md) + [disp_array_exp_a_sqr_bfp](../modules/disp_array_exp_a_sqr_bfp.md) / [disp_array_exp_b_sqr_bfp](../modules/disp_array_exp_b_sqr_bfp.md))
