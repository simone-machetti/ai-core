# Exponent Dispatch (Square-BFP) Testbench

## Purpose

`tb_disp_array_exp_sqr_bfp` verifies the two square-variant BFP exponent dispatchers [disp_array_exp_a_sqr_bfp](../modules/disp_array_exp_a_sqr_bfp.md) + [disp_array_exp_b_sqr_bfp](../modules/disp_array_exp_b_sqr_bfp.md) together. For each of the 11 modes it drives the mode's dispatch control vectors (block selects + per-DP8 idle zero — the same tables as [tb_disp_array_sqr](./tb_disp_array_sqr.md)), pushes `NUM_RAND` random exponent words plus a directed ramp through the input registers, and checks every DP8 exponent output against a golden router model.

## Parameters

| Parameter  | Default | Description                                       |
| ---------- | ------- | ------------------------------------------------- |
| `NUM_RAND` | `500`   | Random exponent vectors per mode (and per sweep). |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=disp_array_exp_sqr_bfp
```

## What it checks

| Property         | Check                                                                                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Exponent routing | every DP8 exponent output equals the golden router model (block-select, high/low B split, per-DP8 `zero_i` mask), all 11 modes + a random-control sweep. |

Any mismatch is **fatal**. The bench dumps `activity.vcd`.

## How it checks

### The golden router

Unlike the baseline-BFP dispatchers (which key idle-zeroing off the `CTR` half codes), the square variant masks per **DP8** on `zero_i`. The model applies block-select, the high/low B split, and that per-DP8 mask. **Modes 5/6** are the directed check that a partly-idle pair masks the right half while its sibling survives — mode 5 idles alternating DP8s, mode 6 the whole second half. A final sweep drives fully random selects and per-DP8 zero bits to cover control combinations no mode produces.

### Drive/sample timing

The dispatchers register their exponent inputs, so each vector is clocked through before the outputs are sampled.

Source: [tb_disp_array_exp_sqr_bfp.sv](../../tb/tb_disp_array_exp_sqr_bfp.sv) — DUT: [disp_array_exp_a_sqr_bfp](../modules/disp_array_exp_a_sqr_bfp.md) + [disp_array_exp_b_sqr_bfp](../modules/disp_array_exp_b_sqr_bfp.md)
