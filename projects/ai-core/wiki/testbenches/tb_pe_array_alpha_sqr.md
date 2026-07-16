# PE Array Alpha (Square) Testbench

## Purpose

`tb_pe_array_alpha_sqr` verifies [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md) **driven through the square A dispatcher** [disp_array_a_sqr](../modules/disp_array_a_sqr.md) — the same `disp → array` structure as [tb_pe_array_sqr](./tb_pe_array_sqr.md). For each of the 11 modes it pushes `NUM_RAND` corner-biased random 256-bit A operands, lets the dispatcher center/idle-zero them, and checks every tap at the mode's read level against a golden that recomputes the tree.

## Parameters

| Parameter  | Default | Description                      |
| ---------- | ------- | -------------------------------- |
| `NUM_RAND` | `200`   | Random operand vectors per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_alpha_sqr
```

## What it checks

| Property         | Check                                                                              |
| ---------------- | ---------------------------------------------------------------------------------- |
| Tree correctness | every read-level tap resolves (`$signed(sum) + $signed(carry)`) to the golden tree |

Any mismatch is **fatal**.

## How it checks

The golden reads the **dispatched** (centered) `a_dp8` off the DUT and applies the α bias per DP8, so the dispatcher, the α DP8 bias ([gate_n_sqr](../modules/gate_n_sqr.md)) and the tree are checked as one path:

```
ALPHA_DP8 = Σ_k 16·(AH_k − 8·bu)² + (AL_k − 8·bu)²        bu = ~is_signed_b
```

where `AH_k − 8·bu` is `is_signed_b ? AH_k : AH_k − 8` (and likewise AL) — mirroring `gate_n_sqr`. Then the same block-negate as the PE (`negd ? −ALPHA_DP8−2 : ALPHA_DP8`), the crossed 4-level weighted tree (`SEL_SHIFT_LUT` gates the `<<8`/`<<4`/`<<8`), and `resolve_tap` at `TAP_LEVEL[mode]`. Mode tables (`SEL_A`, `IS_SIGNED_A`/`IS_SIGNED_B`, `ZERO_I_LUT`, `NEG_I`, `SEL_SHIFT_LUT`, `TAP_LEVEL`) are copied from [tb_pe_array_sqr](./tb_pe_array_sqr.md); the B side is dropped.

**Idle** DP8s (modes 5/6) are clean without special-casing: `is_signed_b = 1` on a dispatcher-zeroed A gives `ALPHA_DP8 = 0`, which the golden reproduces.

### Drive/sample timing

The dispatcher and the α array both register, so each vector is applied and clocked `repeat(2) @(posedge clk_i); #1;` before the taps are sampled. Corner-biased operands (`0x00`/`0xFF`/`0x80`/`0x7F`/`0x88`) stress the bias/sign boundary.

Verified: 11 modes × 200 vectors, 0 mismatches, `-Wall` clean — `pe_array_alpha_sqr: all 11 modes x 200 random tests PASSED!`.

Source: [tb_pe_array_alpha_sqr.sv](../../tb/tb_pe_array_alpha_sqr.sv) — DUT: [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md) (through [disp_array_a_sqr](../modules/disp_array_a_sqr.md))
