# BFP Aligner Testbench

## Purpose

`tb_align_bfp` verifies the multi-exponent aligner [align_bfp](../modules/align_bfp.md) — the binary tree of [align_cell_bfp](../modules/align_cell_bfp.md)s — against a flat value-level golden. It instantiates a **signed** and an **unsigned** tree sharing the same stimulus, and proves that the tree's cascaded per-level shifts **compose to the single flat shift**.

## Parameters

| Parameter   | Default | Description                          |
| ----------- | ------- | ------------------------------------ |
| `WIDTH`     | `20`    | Row width.                           |
| `SIZE`      | `1`     | Rows per bundle.                     |
| `NUM_EXP`   | `8`     | Bundles / exponents into the tree.   |
| `EXP_WIDTH` | `8`     | Exponent width.                      |
| `NUM_RAND`  | `2000`  | Random vectors.                      |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=align_bfp
```

## What it checks

| Property   | Check                                                                                                                                                            |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Flat shift | every row of every bundle equals the input row right-shifted by `(max_exp − bundle_exp)` — **arithmetic** for the signed tree, **logical** for the unsigned one. |
| Exponent   | `exp_o` equals the maximum of **all** input exponents.                                                                                                           |

Any mismatch is **fatal**.

## How it checks

The golden is the flat, single-shift reference: for a global `max`, each bundle is shifted right by its own delta in one step, and the tree's output must match that regardless of how the cascade split the shift across levels. Exponents are drawn as corner-biased deltas around a common base, with three directed patterns:

- an **all-equal** pass that must be **bit-transparent** (the pure-integer anchor);
- a **one-hot max** pattern that deep-flushes every other bundle (the widest shifts);
- random deltas over the legal range.

Row corners use the named constants (`ZERO`, `ALL_ONES`, `MAX_POS`, `MIN_NEG`).

Source: [tb_align_bfp.sv](../../tb/tb_align_bfp.sv) — DUT: [align_bfp](../modules/align_bfp.md)
