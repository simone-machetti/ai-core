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
| `WIDTH`     | 8     | Bit width of each input word.                 |
| `SIZE`      | 4     | Number of input words.                        |
| `EXT`       | 4     | Number of bits added at the top of each word. |
| `IS_SIGNED` | 1     | `1` = sign-extend, `0` = zero-extend.         |

`OUT_WIDTH` (derived) `= WIDTH + EXT`.

## Interface

| Signal        | Dir | Width                | Description                                   |
| ------------- | --- | -------------------- | --------------------------------------------- |
| `in_i`        | in  | `SIZE` × `WIDTH`     | Input words — unpacked array `[0:SIZE-1]`.    |
| `out_o`       | out | `SIZE` × `OUT_WIDTH` | Extended words — unpacked array `[0:SIZE-1]`. |

## Internal logic

Purely combinational, applied independently to each input `i`: prepend `EXT` bits to `in_i[i]` — copies of the sign bit `in_i[i][WIDTH-1]` when `IS_SIGNED`, otherwise zeros. Signedness is a compile-time parameter — a fixed datapath property, same rationale as `cpr_w_n` (which instantiates this module with `.IS_SIGNED(IS_SIGNED)`).

## Instantiation

```systemverilog
ext_n #(.WIDTH(8), .SIZE(4), .EXT(4), .IS_SIGNED(1'b1)) ext_n_i (
    .in_i(in), .out_o(out)
);
```

Source: [ext_n.sv](../../rtl/ext_n.sv)
