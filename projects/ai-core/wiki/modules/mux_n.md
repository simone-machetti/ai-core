---
type: module
title: Multiplexer N
description: Parameterized SIZE-to-1 multiplexer over WIDTH-bit words.
resource: rtl/mux_n.sv
tags: [module, routing, mux]
timestamp: 2026-07-01
---

# Multiplexer N

`mux_n` — Parameterized `SIZE`-to-1 multiplexer over `WIDTH`-bit words.

## Purpose

Selects one of `SIZE` input words onto the output under `sel_i`. Values that must be chosen together — such as the high and low halves of a single wider value — are merged into one `WIDTH`-bit input and selected as one, so a plain N-to-1 select covers the paired case without any extra logic.

## Parameters

| Parameter | Default | Description                            |
| --------- | ------- | -------------------------------------- |
| `WIDTH`   | 8       | Bit width of each input/output word.   |
| `SIZE`    | 4       | Number of input words to select among. |

`SEL_W` (derived) `= $clog2(SIZE)` is the select width.

## Interface

| Signal  | Dir | Width            | Description                                  |
| ------- | --- | ---------------- | -------------------------------------------- |
| `in_i`  | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`.   |
| `sel_i` | in  | `SEL_W`          | Index of the input word to drive the output. |
| `out_o` | out | `WIDTH`          | Selected input word.                         |

## Internal logic

Purely combinational: `out_o = in_i[sel_i]`, a single dynamic index into the input array — no clock, no storage. For paired selection the caller concatenates the pair into one `WIDTH`-bit input rather than selecting two narrower words separately.

## Instantiation

```systemverilog
mux_n #(.WIDTH(8), .SIZE(4)) mux_n_i (
    .in_i(in), .sel_i(sel), .out_o(out)
);
```

Source: [mux_n.sv](../../rtl/mux_n.sv)
