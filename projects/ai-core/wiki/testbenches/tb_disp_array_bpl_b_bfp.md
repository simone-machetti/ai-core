# Dispatch Array (Bit-Plane-B BFP) Testbench

## Purpose

`tb_disp_array_bpl_b_bfp` verifies the bit-plane-B dispatch **pair** — [disp_array_a_bpl_b_bfp](../modules/disp_array_a_bpl_b_bfp.md) and the plain [disp_array_b](../modules/disp_array_b.md) — against a golden model, for all 11 operating modes. Both are driven with the mode's *real* dispatch control vector: block selects, B-gate ops and per-DP8 A signedness taken verbatim from `ctrl`'s lookup tables.

## Parameters

| Parameter  | Default | Description                              |
| ---------- | ------- | ---------------------------------------- |
| `NUM_RAND` | `500`   | Random 256-bit operand vectors per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=disp_array_bpl_b_bfp
```

## What it checks

| Output        | Golden                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------ |
| `a_dp8_o`     | block select → duplication onto both DP8s of a pair → signedness-aware widening to 9 bits. |
| `a_sum_dp8_o` | the four pairwise sums at 10 bits.                                                         |
| `b_dp8_o`     | block select → high/low split → per-int4 gate, as raw gated nibbles.                       |

Any mismatch is **fatal**.

## How it checks

### The A side is where the work is

This is the mirror of [tb_disp_array_bpl_a_bfp](./tb_disp_array_bpl_a_bfp.md): there the golden had to reproduce the *B* gate chain, here it reproduces the *A* resolution. The model covers the block select, the duplication onto both DP8s of a pair, the signedness-aware widening, and the four pairwise sums — which is precisely the "one gate per pair, routing per DP8" structure, checked from the outside so a wrongly-shared gate would show as a mismatch on one of the two DP8s.

### The B side still exercises the carry chain

Even though B is now dispatched by the unmodified [disp_array_b](../modules/disp_array_b.md), it is checked here rather than assumed: block select, the fixed high/low split, and the per-int4 gate **including the two's-complement carry that ripples from the low half into the high half**. The negate modes are driven with `ctrl`'s carry-chained control (`GATE_NEG` on the low half, `GATE_NEG_CARRY` on the high half), so the cross-half carry is exercised.

Result: **11/11 modes PASSED**, 0 mismatches.

Source: [tb_disp_array_bpl_b_bfp.sv](../../tb/tb_disp_array_bpl_b_bfp.sv) — DUTs: [disp_array_a_bpl_b_bfp](../modules/disp_array_a_bpl_b_bfp.md), [disp_array_b](../modules/disp_array_b.md)
