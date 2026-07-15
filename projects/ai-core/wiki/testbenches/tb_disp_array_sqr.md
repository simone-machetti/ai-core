# Dispatch Array (Square) Testbench

## Purpose

`tb_disp_array_sqr` verifies the square dispatchers [disp_array_a_sqr](../modules/disp_array_a_sqr.md) and [disp_array_b_sqr](../modules/disp_array_b_sqr.md) together. For each of the 11 modes it drives the mode's control vectors and checks every DP8 output against a golden model that **routes** the block, **centers** each nibble (flip MSB iff unsigned; A's low nibble always), and forces **idle** DP8s to a real zero.

## Parameters

| Parameter  | Default | Description                                                       |
| ---------- | ------- | ----------------------------------------------------------------- |
| `NUM_RAND` | `500`   | Random 256-bit operand vectors per mode (plus one directed ramp). |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=disp_array_sqr
```

## What it checks

| Property              | Check                                                                                         |
| --------------------- | --------------------------------------------------------------------------------------------- |
| Route + center + zero | every `a_dp8_o`/`b_dp8_o` equals the golden (block-select → per-nibble centering → idle-zero) |

Any mismatch is **fatal**.

## How it checks

### Control vectors

The mode tables hold `SEL_A`/`SEL_B` (block routing, same as the baseline), `IS_SIGNED_A`/`IS_SIGNED_B` (per-DP8, from `ctrl`'s LUTs — **with the mode-5 `is_signed_b` idle fix**: its unsigned-`b` idle DP8s are forced signed so a zeroed `b` centers to a real `0`, matching mode 6), and `ZERO_I` (per-DP8 idle set, only modes 5/6). `set_controls(mi)` drives them onto the DUTs (`zero_i` is shared by both dispatchers).

### The golden

`center_a`/`center_b` mirror the gates — flip AH MSB iff unsigned + AL MSB always (A), flip nibble MSB iff unsigned (B), return `0` when idle. The check routes `a_sel`/`b_sel` per `SEL_*`, then compares each DP8 (B: even DP8 = high half, odd = low half):

```systemverilog
a_exp[2*p+d] = center_a(a_sel, IS_SIGNED_A[mi][2*p+d], ZERO_I_LUT[mi][2*p+d]);
b_exp[2*p+0] = center_b(b_sel[63:32], IS_SIGNED_B[mi][2*p+0], ZERO_I_LUT[mi][2*p+0]);
b_exp[2*p+1] = center_b(b_sel[31:0],  IS_SIGNED_B[mi][2*p+1], ZERO_I_LUT[mi][2*p+1]);
```

### Drive/sample timing

The dispatchers register their input, so each vector is applied, clocked one `@(posedge clk_i)`, then checked after `#1`. `NUM_RAND` random vectors plus one directed ramp run per mode.

If every vector passes, the tb prints `disp_array_sqr: all 11 modes x (N random + ramp) tests PASSED!` and calls `$finish`.

Source: [tb_disp_array_sqr.sv](../../tb/tb_disp_array_sqr.sv) — DUTs: [disp_array_a_sqr](../modules/disp_array_a_sqr.md), [disp_array_b_sqr](../modules/disp_array_b_sqr.md)
