---
type: module
title: Booth Radix-4 Cell
description: Radix-4 Booth encoder cell — one 3-bit selector to one partial product of the multiplicand.
resource: rtl/booth_r4_cell.sv
tags: [module, arithmetic, booth]
timestamp: 2026-07-01
---

# Booth Radix-4 Cell

`booth_r4_cell` — Radix-4 Booth encoder cell: turns one 3-bit selector into a single partial product of the multiplicand.

## Purpose

Generates one radix-4 Booth partial product — one of `{0, +B, +2B, -2B, -B}` of the multiplicand — chosen by a 3-bit selector. The output is two bits wider than the multiplicand to hold the `2B` case. It is instantiated `PP_SIZE` times by [booth_r4](booth_r4.md).

## Parameters

| Parameter  | Default | Description                             |
| ---------- | ------- | --------------------------------------- |
| `IN_WIDTH` | 16      | Bit width of the multiplicand `mult_i`. |

`OUT_WIDTH` (derived) `= IN_WIDTH + 2`.

## Interface

| Signal        | Dir | Width       | Description                                                   |
| ------------- | --- | ----------- | ------------------------------------------------------------- |
| `mult_i`      | in  | `IN_WIDTH`  | Multiplicand.                                                 |
| `sel_i`       | in  | 3           | Radix-4 Booth selector (two multiplier bits + overlap).       |
| `is_signed_i` | in  | 1           | Multiplicand extension: `1` = sign-extend, `0` = zero-extend. |
| `pp_o`        | out | `OUT_WIDTH` | Partial product.                                              |

## Internal logic

The multiplicand is first extended by two bits (sign- or zero-extended per `is_signed_i`). A `case` on `sel_i` then selects the operation: `001`/`010` → `+B`, `011` → `+2B` (left shift), `100` → `-2B`, `101`/`110` → `-B`, and `000`/`111` → `0`. Purely combinational; no clock, no storage.

## Instantiation

```systemverilog
booth_r4_cell #(.IN_WIDTH(8)) booth_r4_cell_i (
    .mult_i(a), .sel_i(sel), .is_signed_i(is_signed), .pp_o(pp)
);
```

Source: [booth_r4_cell.sv](../../rtl/booth_r4_cell.sv)
