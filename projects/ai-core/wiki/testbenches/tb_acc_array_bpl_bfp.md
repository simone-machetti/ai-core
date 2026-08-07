# Accumulator Array (Bit-Plane BFP) Testbench

## Purpose

`tb_acc_array_bpl_bfp` verifies the **full bit-plane BFP PE datapath** with the integer datapath alongside as reference. The mantissa dispatchers feed both `pe_array → acc_array` (baseline) and [pe_array_bpl_bfp](../modules/pe_array_bpl_bfp.md) → [acc_array_bpl_bfp](../modules/acc_array_bpl_bfp.md), while the exponent dispatchers feed the BFP tree and accumulator. The check point is `pe_out` — the PE's real output, after tap resolve, accumulate and lane fusion.

## Parameters

| Parameter  | Default | Description                             |
| ---------- | ------- | --------------------------------------- |
| `NUM_RAND` | `2000`  | Random A,B matrix pairs per mode.       |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass.    |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=acc_array_bpl_bfp
```

## What it checks

| Pass | Check |
| ---- | ----- |
| A — equal exponents | the bit-plane output equals the baseline at `pe_out` — single-shot **and** through the `seed + NUM_ACC−1` feedback accumulation — while the baseline itself matches the matmul golden (`seed + NUM_ACC · result`); every accumulator exponent equals the common scale. |
| B — per-mode BFP exponents | the running accumulator scale equals the tap scale, and the accumulator value is exactly `(seed >>> tap_exp) + NUM_ACC · tap`. |

**All 8 lanes** of every mode must match — the check is not restricted to the lanes a mode nominally uses. Any mismatch is **fatal**.

## How it checks

### Pass B's closed form

The seed is placed at the minimum scale `0`. A min-scale seed floors **once** on the first alignment, and every later feedback add then sits at the stable tap scale, so the accumulator value collapses to `(seed >>> tap_exp) + NUM_ACC · tap` read directly from the BFP tap. That makes Pass B a bit-exact check of the in-loop alignment and the running-max exponent rather than a windowed one.

### Why the accumulator is where the idle-DP8 bug surfaced

This bench and [tb_top_NxN_bpl_bfp](./tb_top_NxN_bpl_bfp.md) are what caught the **non-canonical zero**: with `is_signed_a` left set on an idle DP8, [dp_8_bpl_bfp](../modules/dp_8_bpl_bfp.md)'s weight-2⁷ fold produces a carry-save pair with `s + c = 0` but `s ≠ 0`, and the BFP right-shift alignment in the accumulate loop destroys that cancellation — a one-LSB error that only appears once an aligner actually shifts. The fix lives in [top_NxN_bpl_bfp](../architectures/top_NxN_bpl_bfp.md), which masks `is_signed_a` from `ctrl`'s zero gate codes.

Result: **11/11 modes, all lanes, 0 mismatches**.

Source: [tb_acc_array_bpl_bfp.sv](../../tb/tb_acc_array_bpl_bfp.sv) — DUT: [acc_array_bpl_bfp](../modules/acc_array_bpl_bfp.md) (whole path from the dispatchers; reference `pe_array` → [acc_array](../modules/acc_array.md))
