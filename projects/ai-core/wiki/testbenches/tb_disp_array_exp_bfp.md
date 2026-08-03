# Exponent Dispatch (BFP) Testbench

## Purpose

`tb_disp_array_exp_bfp` verifies the two BFP exponent dispatchers [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) + [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md) together. For each of the 11 modes it drives the mode's dispatch control vector (block selects + B-gate ops — the same tables as [tb_disp_array](./tb_disp_array.md)), pushes `NUM_RAND` random exponent words plus a directed ramp through the input registers, and checks every DP8 exponent output against a golden router model.

## Parameters

| Parameter  | Default | Description                                       |
| ---------- | ------- | ------------------------------------------------- |
| `NUM_RAND` | `500`   | Random exponent vectors per mode (and per sweep). |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=disp_array_exp_bfp
```

## What it checks

| Property         | Check                                                                                                                                                      |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Exponent routing | every DP8 exponent output equals the golden router model (block-select, high/low B split, per-half ZERO-only gate), all 11 modes + a random-control sweep. |

Any mismatch is **fatal**. The bench dumps `activity.vcd`.

## How it checks

### The golden router

The model applies block-select, the high/low B split (the two half exponents to the even/odd DP8s), and a **per-half ZERO-only gate**: the `ZERO` code masks the half, while `NEG` / `NEG_CARRY` pass the exponent **unchanged**. Two directed observations fall out:

- **Modes 10/11** — the directed check that a mantissa negation **never touches its scale** (the sign flip lives in the mantissa path, not the exponent).
- **Modes 5/6** — the check that an idle half is masked while its sibling half survives.

A final sweep drives fully random selects and gate ops to cover control combinations no mode produces.

### Drive/sample timing

The dispatchers register their exponent inputs, so each vector is clocked through before the outputs are sampled.

Source: [tb_disp_array_exp_bfp.sv](../../tb/tb_disp_array_exp_bfp.sv) — DUT: [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) + [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md)
