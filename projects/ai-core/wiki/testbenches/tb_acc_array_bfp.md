# Accumulator Array (BFP) Testbench

## Purpose

`tb_acc_array_bfp` is the **whole-datapath oracle** for the baseline-BFP PE. It wires the full BFP path —

```
disp_array_a / disp_array_b (+ disp_array_exp_a_bfp / disp_array_exp_b_bfp)
   → pe_array_bfp → acc_array_bfp
```

— with the integer path `pe_array → acc_array` running **alongside** from the same dispatched operands as the reference. The mantissa dispatchers feed both; the exponent dispatchers feed the BFP tree and accumulator. Because the BFP path is bit-transparent when exponents are equal, the golden, operand packing and result reconstruction are reused verbatim from [tb_acc_array](./tb_acc_array.md).

## Parameters

| Parameter  | Default | Description                          |
| ---------- | ------- | ------------------------------------ |
| `NUM_RAND` | `2000`  | Random A,B matrix pairs per mode.    |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=acc_array_bfp
```

## What it checks

| Pass                   | Check                                                                                                                                                                                                                                                            |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A — equal exponents    | every BFP aligner transparent → BFP `pe_out` **bit-identical** to the baseline (single-shot **and** through `seed + (NUM_ACC−1)` feedback), the baseline matches the matmul golden (`seed + NUM_ACC·X`), and every accumulator exponent equals the common scale. |
| B — distinct exponents | with the seed at the **minimum scale 0**, the running accumulator scale equals the tap scale and the value is exactly `(seed >>> tap_exp) + NUM_ACC·tap`, read directly from the BFP tap.                                                                        |

Any mismatch is **fatal**.

## How it checks

For each mode: build `A`, `B` corner-biased; compute the golden `X = A·B` (real, or complex with four real products); pack into the two 256-bit operand words at the Storage-table positions; run both paths; reconstruct each `pe_out` from its lane (L0) or fused `{H(even), L(odd)}` 40-bit pair (L1..L3) and compare.

### Pass B — the in-loop alignment

A min-scale seed floors **once** on the first alignment, and every later feedback add sits at the stable tap scale, so the closed-form `(seed >>> tap_exp) + NUM_ACC·tap` is a **bit-exact** check of [acc_array_bfp](../modules/acc_array_bfp.md)'s in-loop [align_cell_bfp](../modules/align_cell_bfp.md) and its running-max exponent register — not a window. Per-mode BFP exponents are drawn from the legal tie groups.

Source: [tb_acc_array_bfp.sv](../../tb/tb_acc_array_bfp.sv) — DUT: [acc_array_bfp](../modules/acc_array_bfp.md) (through [pe_array_bfp](../modules/pe_array_bfp.md), baseline [pe_array](../modules/pe_array.md) → [acc_array](../modules/acc_array.md) alongside)
