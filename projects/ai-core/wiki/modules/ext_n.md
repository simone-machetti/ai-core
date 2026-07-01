---
type: module
title: Extender N
description: Parameterized extender — widens each of SIZE WIDTH-bit inputs by EXT bits (sign or zero).
resource: rtl/ext_n.sv
tags: [module, routing, extender]
timestamp: 2026-07-01
---

# Extender N

`ext_n` — Parameterized extender: widens each of `SIZE` `WIDTH`-bit inputs by `EXT` bits, to `WIDTH + EXT`.

## Purpose

Sign- or zero-extends a group of values to a wider field — the width-matching step before values of differing widths share an adder or compressor. It is reused inside the compressors [cpr_c_n](cpr_c_n.md) and [cpr_w_n](cpr_w_n.md) to widen their inputs.

## Parameters

| Parameter | Default | Description                                   |
| --------- | ------- | --------------------------------------------- |
| `WIDTH`   | 8       | Bit width of each input word.                 |
| `SIZE`    | 4       | Number of input words.                        |
| `EXT`     | 4       | Number of bits added at the top of each word. |

`OUT_WIDTH` (derived) `= WIDTH + EXT`.

## Interface

| Signal        | Dir | Width                | Description                                   |
| ------------- | --- | -------------------- | --------------------------------------------- |
| `in_i`        | in  | `SIZE` × `WIDTH`     | Input words — unpacked array `[0:SIZE-1]`.    |
| `is_signed_i` | in  | 1                    | `1` = sign-extend, `0` = zero-extend.         |
| `out_o`       | out | `SIZE` × `OUT_WIDTH` | Extended words — unpacked array `[0:SIZE-1]`. |

## Internal logic

Purely combinational, applied independently to each input `i` (all sharing `is_signed_i`): prepend `EXT` bits to `in_i[i]` — copies of the sign bit `in_i[i][WIDTH-1]` when `is_signed_i`, otherwise zeros.

## Instantiation

```systemverilog
ext_n #(.WIDTH(8), .SIZE(4), .EXT(4)) ext_n_i (
    .in_i(in), .is_signed_i(is_signed), .out_o(out)
);
```

Source: [ext_n.sv](../../rtl/ext_n.sv)
