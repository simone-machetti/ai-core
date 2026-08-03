# PE Array Alpha (Square-BFP) Testbench

## Purpose

`tb_pe_array_alpha_sqr_bfp` verifies [pe_array_alpha_sqr_bfp](../modules/pe_array_alpha_sqr_bfp.md) — the tree-less per-row `−α` generator — driven through the real square A dispatcher [disp_array_a_sqr](../modules/disp_array_a_sqr.md). For each of the 11 modes it pushes `NUM_RAND` corner-biased random 256-bit A operands, lets the dispatcher center / idle-zero them, and checks every one of the 16 per-DP8 `−α` carry-save outputs against an independent software golden.

## Parameters

| Parameter  | Default | Description                      |
| ---------- | ------- | -------------------------------- |
| `NUM_RAND` | `500`   | Random operand vectors per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_alpha_sqr_bfp
```

## What it checks

| Property     | Check                                                                                           |
| ------------ | ----------------------------------------------------------------------------------------------- |
| Per-DP8 `−α` | each of the 16 `−α` carry-save pairs resolves to `−ALPHA_DP8 − 2` (idle DP8 → `−2`), all modes. |

Any mismatch is **fatal**.

## How it checks

### The golden

The golden replicates [dp_8_alpha_sqr](../modules/dp_8_alpha_sqr.md) on the **dispatched** operands read straight off the DUT inputs:

```
ALPHA_DP8 = 2⁴ · Σ_k arg(AH_k)² + Σ_k arg(AL_k)² ,
arg(n)    = signed(n) − 8·(~is_signed_b)          (the gate_n_sqr removed-B bias)
```

[pe_array_alpha_sqr_bfp](../modules/pe_array_alpha_sqr_bfp.md) emits `−α` via a one's-complement of the carry-save pair, so each output resolves to `−ALPHA_DP8 − 2` — the deferred `+2` being folded downstream into [const_sqr_bfp](../modules/const_sqr_bfp.md). An idle DP8 (`ctrl` forces `is_signed_b = 1`, A dispatcher-zeroed) gives `ALPHA_DP8 = 0` → resolve `−2`. This generator is combinational and tree-less (its register lives in [pe_array_sqr_bfp](../modules/pe_array_sqr_bfp.md)'s L0), so there is no tap sweep — the 16 outputs are checked directly.

### Drive/sample timing

The dispatcher registers its input, so each vector is clocked through before the outputs are sampled. Operands are corner-biased to stress the square-sum sign-consistency.

Source: [tb_pe_array_alpha_sqr_bfp.sv](../../tb/tb_pe_array_alpha_sqr_bfp.sv) — DUT: [pe_array_alpha_sqr_bfp](../modules/pe_array_alpha_sqr_bfp.md) (through [disp_array_a_sqr](../modules/disp_array_a_sqr.md))
