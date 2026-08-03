# PE Array Beta (Square-BFP) Testbench

## Purpose

`tb_pe_array_beta_sqr_bfp` verifies [pe_array_beta_sqr_bfp](../modules/pe_array_beta_sqr_bfp.md) — the tree-less per-column `−β` generator — driven through the real square B dispatcher [disp_array_b_sqr](../modules/disp_array_b_sqr.md). For each of the 11 modes it pushes `NUM_RAND` corner-biased random 256-bit B operands, lets the dispatcher center / idle-zero them, and checks every one of the 16 per-DP8 `−β` carry-save outputs against an independent software golden.

## Parameters

| Parameter  | Default | Description                      |
| ---------- | ------- | -------------------------------- |
| `NUM_RAND` | `500`   | Random operand vectors per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_beta_sqr_bfp
```

## What it checks

| Property     | Check                                                                                          |
| ------------ | ---------------------------------------------------------------------------------------------- |
| Per-DP8 `−β` | each of the 16 `−β` carry-save pairs resolves to `−BETA_DP8 − 2` (idle DP8 → `−2`), all modes. |

Any mismatch is **fatal**.

## How it checks

### The golden

The golden replicates [dp_8_beta_sqr](../modules/dp_8_beta_sqr.md) on the **dispatched** operands read straight off the DUT inputs — the single `b` squared twice, high and low block:

```
BETA_DP8  = 2⁴ · Σ_k arg_h(B_k)² + Σ_k arg_l(B_k)² ,
arg_h(b)  = signed(b) − 8·(~is_signed_a)     (gate_n_sqr, high block)
arg_l(b)  = zero ? 0 : signed(b) − 8         (gate_n_beta_sqr, low block)
```

[pe_array_beta_sqr_bfp](../modules/pe_array_beta_sqr_bfp.md) emits `−β` via a one's-complement of the carry-save pair, so each output resolves to `−BETA_DP8 − 2` — the deferred `+2` being folded downstream into [const_sqr_bfp](../modules/const_sqr_bfp.md). An idle DP8 (`zero_i`, B dispatcher-zeroed, `is_signed_a = 1`) gives `BETA_DP8 = 0` → resolve `−2`. Combinational and tree-less (its register lives in [pe_array_sqr_bfp](../modules/pe_array_sqr_bfp.md)'s L0), so the 16 outputs are checked directly with no tap sweep.

### Drive/sample timing

The dispatcher registers its input, so each vector is clocked through before the outputs are sampled. Operands are corner-biased to stress the square-sum sign-consistency.

Source: [tb_pe_array_beta_sqr_bfp.sv](../../tb/tb_pe_array_beta_sqr_bfp.sv) — DUT: [pe_array_beta_sqr_bfp](../modules/pe_array_beta_sqr_bfp.md) (through [disp_array_b_sqr](../modules/disp_array_b_sqr.md))
