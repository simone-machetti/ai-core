# BFP Alignment Cell Testbench

## Purpose

`tb_align_cell_bfp` verifies the two-bundle align cell [align_cell_bfp](../modules/align_cell_bfp.md) against a value-level golden. It instantiates an **H/L lane pair** (both signed, shared exponents, chain wired `H → L`) plus an **unsigned standalone** instance sharing the H stimulus, and checks every vector **twice** — with the L chain disabled and enabled.

## Parameters

| Parameter   | Default | Description                          |
| ----------- | ------- | ------------------------------------ |
| `WIDTH`     | `20`    | Row width.                           |
| `SIZE_0`    | `2`     | Rows in bundle 0.                    |
| `SIZE_1`    | `2`     | Rows in bundle 1.                    |
| `EXP_WIDTH` | `8`     | Exponent width.                      |
| `NUM_RAND`  | `2000`  | Random vectors.                      |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=align_cell_bfp
```

## What it checks

| Property            | Check                                                                                                                                                                         |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shift to max        | each row of the smaller-exponent bundle equals the row right-shifted by `(max_exp − bundle_exp)` — **arithmetic** for the signed instances, **logical** for the unsigned one. |
| Winner pass-through | the larger-exponent (winner) bundle passes through **bit-identical**.                                                                                                         |
| Chained fusion      | the chained L instance shifts the fused `2·WIDTH` word `{H row, L row}` (cross-boundary fill).                                                                                |
| Exponent            | `exp_o` equals the max on all instances.                                                                                                                                      |

Any mismatch is **fatal**.

## How it checks

The golden is value-level: it computes each shifted row directly from the input rows and the exponent delta, so the DUT's `sub_n_bfp` compare, its `shift_n_bfp` shift, and the `mux_n` swap/un-swap are checked as one. Exponent deltas are corner-biased around `0 / 1 / WIDTH / 2·WIDTH` (the boundaries where the shift saturates or crosses the lane), and the row corners use the named constants (`ZERO`, `ALL_ONES`, `MAX_POS`, `MIN_NEG`) to stress sign-fill.

Source: [tb_align_cell_bfp.sv](../../tb/tb_align_cell_bfp.sv) — DUT: [align_cell_bfp](../modules/align_cell_bfp.md)
