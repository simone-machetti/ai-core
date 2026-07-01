---
type: module
title: Booth Radix-4
description: Radix-4 Booth partial-product generator with per-operand signedness.
resource: rtl/booth_r4.sv
tags: [module, arithmetic, booth, multiplier]
timestamp: 2026-07-01
---

# Booth Radix-4

`booth_r4` — Radix-4 Booth multiplier partial-product generator with per-operand signedness: recodes the multiplier and emits `PP_SIZE` partial products of the multiplicand.

## Purpose

Produces the radix-4 Booth partial products of `a_i × b_i` — `PP_SIZE = IN_WIDTH_B / 2 + 1` products, each `IN_WIDTH_A + 2` bits — roughly halving the partial-product count versus a plain array. The multiplier `b_i` (recoded) should carry the narrower operand so the fewest partial products are generated (e.g. the 4-bit operand of an 8×4 multiply). Signedness is per operand and runtime: `is_signed_a_i` sets the multiplicand extension, `is_signed_b_i` sets the multiplier extension.

## Parameters

| Parameter    | Default | Description                                                        |
| ------------ | ------- | ------------------------------------------------------------------ |
| `IN_WIDTH_A` | 8       | Bit width of the multiplicand `a_i`.                               |
| `IN_WIDTH_B` | 4       | Bit width of the multiplier `b_i` (recoded; the narrower operand). |

`PP_SIZE` (derived) `= IN_WIDTH_B / 2 + 1`; `PP_WIDTH` (derived) `= IN_WIDTH_A + 2`. `PP_SIZE` carries the count needed for an unsigned multiplier — one more than a signed-only recoder.

## Interface

| Signal          | Dir | Width                  | Description                                           |
| --------------- | --- | ---------------------- | ----------------------------------------------------- |
| `a_i`           | in  | `IN_WIDTH_A`           | Multiplicand.                                         |
| `b_i`           | in  | `IN_WIDTH_B`           | Multiplier (recoded into Booth selectors).            |
| `is_signed_a_i` | in  | 1                      | Multiplicand extension: `1` = signed, `0` = unsigned. |
| `is_signed_b_i` | in  | 1                      | Multiplier extension: `1` = signed, `0` = unsigned.   |
| `pp_o`          | out | `PP_SIZE` × `PP_WIDTH` | Partial products — unpacked array `[0:PP_SIZE-1]`.    |

## Internal logic

The multiplier `b_i` is extended above its MSB — sign-extended when `is_signed_b_i`, else zero-extended — and given a trailing zero, then split into `PP_SIZE` overlapping 3-bit selectors. Each selector drives one radix-4 Booth encoder cell [booth_r4_cell](booth_r4_cell.md) that emits a single partial product from the multiplicand `a_i` (extended per `is_signed_a_i`). The extra top selector is what distinguishes the two multiplier modes: for a signed `b_i` it recodes to `0` (the sign is already carried by the next-lower digit), so the top partial product vanishes; for an unsigned `b_i` it emits a final `{0, +a}` partial product supplying the positive weight of the top multiplier bit. Purely combinational; no clock, no storage.

## Instantiation

```systemverilog
booth_r4 #(.IN_WIDTH_A(8), .IN_WIDTH_B(4)) booth_r4_i (
    .a_i(a), .b_i(b),
    .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
    .pp_o(pp)
);
```

Source: [booth_r4.sv](../../rtl/booth_r4.sv) — Testbench: [tb_booth_r4.sv](../../tb/tb_booth_r4.sv)
