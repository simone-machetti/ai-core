# Accumulator Array (Bit-Plane-B BFP) Testbench

## Purpose

`tb_acc_array_bpl_b_bfp` verifies the **full bit-plane-B BFP PE datapath** — [pe_array_bpl_b_bfp](../modules/pe_array_bpl_b_bfp.md) → [acc_array_bpl_bfp](../modules/acc_array_bpl_bfp.md) — with the integer datapath ([pe_array](../modules/pe_array.md) → [acc_array](../modules/acc_array.md)) alongside as reference. The mantissa dispatchers feed both; the exponent dispatchers feed the BFP tree and accumulator.

## Parameters

| Parameter  | Default | Description                          |
| ---------- | ------- | ------------------------------------ |
| `NUM_RAND` | `2000`  | Random `A,B` matrix pairs per mode.  |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=acc_array_bpl_b_bfp
```

## What it checks

Every mode runs twice per vector:

| Pass | Exponents                         | Checks                                                                                                                                                                                                                                                                                                                 |
| ---- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A    | equal                             | every BFP aligner is bit-transparent, so the BFP output is **bit-identical** to the baseline at `pe_out` — single-shot and through the seed + `NUM_ACC−1` feedback accumulation — while the baseline itself matches the matmul golden (`seed + NUM_ACC × result`); every accumulator exponent equals the common scale. |
| B    | per-mode BFP, seed at min scale 0 | the running accumulator scale equals the tap scale, and the accumulator value is exactly `(seed >>> tap_exp) + NUM_ACC × tap`, read directly from the BFP tap.                                                                                                                                                         |

Any mismatch is **fatal**.

## How it checks

### Why pass A can demand bit-identity here

At the tap level [tb_pe_array_bpl_b_bfp](./tb_pe_array_bpl_b_bfp.md) can only compare resolved *values*, because the bit-plane tree's carry-save encoding differs from the Booth tree's. By `pe_out` the accumulator has **resolved** the carry-save pair into a single word, so the encoding difference is gone and the stronger bit-identity check applies.

### Why pass B is exact rather than a window

A min-scale seed floors **once** on the first alignment, and every later feedback add sits at the stable tap scale. That makes the closed form `(seed >>> tap_exp) + NUM_ACC × tap` exact rather than bounded — a bit-exact check of the in-loop alignment and the running-max exponent, with no window to hide a small error.

Result: **11/11 modes PASSED**, 0 mismatches.

Source: [tb_acc_array_bpl_b_bfp.sv](../../tb/tb_acc_array_bpl_b_bfp.sv) — DUTs: [pe_array_bpl_b_bfp](../modules/pe_array_bpl_b_bfp.md), [acc_array_bpl_bfp](../modules/acc_array_bpl_bfp.md)
