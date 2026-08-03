# Accumulator Array (Square-BFP) Testbench

## Purpose

`tb_acc_array_sqr_bfp` is the **whole-datapath oracle** for the square-BFP PE. It runs two chains from the same dispatched operands and checks them against a matmul golden — the **three agree**:

```
sqr     : disp_{a,b}_sqr → pe_array_sqr ∥ pe_array_alpha_sqr ∥ pe_array_beta_sqr → const_sqr → acc_array_sqr → pe_out
sqr_bfp : disp_{a,b}_sqr (+ disp_exp_{a,b}_sqr_bfp) → pe_array_{alpha,beta}_sqr_bfp + pe_array_sqr_bfp → acc_array_sqr_bfp → b_pe_out
```

The integer square path is the reference; the golden `X = A·B` is reused verbatim from [tb_acc_array_sqr](./tb_acc_array_sqr.md) (matrices, pack, reconstruction). The per-DP8 `const_dp8_i` the BFP PE needs is **computed here** (a preview of [const_sqr_bfp](../modules/const_sqr_bfp.md), built before that gate): `C_cent = 16·c(nAH) + c(nAL)`, `const = negated ? 2 − C_cent : C_cent + 4` (the `+4` cancelling the two generators' per-DP8 one's-complement deferrals).

## Parameters

| Parameter  | Default | Description                          |
| ---------- | ------- | ------------------------------------ |
| `NUM_RAND` | `2000`  | Random A,B matrix pairs per mode.    |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=acc_array_sqr_bfp
```

## What it checks

| Pass                   | Check                                                                                                                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A — equal exponents    | every aligner transparent → `b_pe_out === pe_out === golden`, single-shot **and** through `seed + (NUM_ACC−1)` feedback; every BFP accumulator exponent equals the common scale.                              |
| B — distinct exponents | `sqr` has no exponents, so the BFP chain is checked against its own tap: the running scale equals the tap scale and `b_pe_out == (seed >>> tap_exp) + NUM_ACC·(tap/2)`, with the seed at the minimum scale 0. |

Any mismatch is **fatal**.

## How it checks

The square-specific controls are the same LUTs the α/β generator benches use — `IS_SIGNED_A/B`, `ZERO_I`, `NEG_I`, `SEL_SHIFT`, `SEL_CONST`. Each result is reconstructed from its lane (L0) or fused `{H(even), L(odd)}` pair (L1..L3).

### Pass B — the in-loop `½` and alignment

Pass B is a **bit-exact** check of [acc_array_sqr_bfp](../modules/acc_array_sqr_bfp.md)'s in-loop [align_cell_bfp](../modules/align_cell_bfp.md), the `÷2`, and the running-max exponent: a min-scale seed floors once, later feedbacks sit at the stable tap scale, and the tap already carries `2·P`, so `(seed >>> tap_exp) + NUM_ACC·(tap/2)` is the closed form. This is where the "no `C`/`c_neg` at the accumulator" and the `EXT = CARRY = 3` `½` path are confirmed.

Source: [tb_acc_array_sqr_bfp.sv](../../tb/tb_acc_array_sqr_bfp.sv) — DUT: [acc_array_sqr_bfp](../modules/acc_array_sqr_bfp.md) (through [pe_array_sqr_bfp](../modules/pe_array_sqr_bfp.md) + [ext_inject_sqr_bfp](../modules/ext_inject_sqr_bfp.md); integer square path alongside)
