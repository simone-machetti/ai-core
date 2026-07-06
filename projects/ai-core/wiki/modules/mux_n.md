---
type: module
title: Multiplexer N
description: Parameterized SIZE-to-1 multiplexer over WIDTH-bit words.
resource: rtl/mux_n.sv
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

`SEL_W` (derived `localparam`) `= (SIZE > 1) ? $clog2(SIZE) : 1` — the select width.

## Interface

| Signal  | Dir | Width            | Description                                  |
| ------- | --- | ---------------- | -------------------------------------------- |
| `in_i`  | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`.   |
| `sel_i` | in  | `SEL_W`          | Index of the input word to drive the output. |
| `out_o` | out | `WIDTH`          | Selected input word.                         |

## Instantiation

```systemverilog
mux_n #(
    .WIDTH (8),
    .SIZE  (4)
) mux_n_i (
    .in_i  (in),
    .sel_i (sel),
    .out_o (out)
);
```

## Internal logic

The module is purely combinational — no clock, no storage. It is a single dynamic array index, plus a small compile-time computation that sizes the select port.

### Select width

```systemverilog
localparam int SEL_W = (SIZE > 1) ? $clog2(SIZE) : 1;
```

`sel_i` must be wide enough to index all `SIZE` words, i.e. `$clog2(SIZE)` bits. The guard handles the degenerate `SIZE == 1` case: `$clog2(1)` is `0`, which would make `sel_i` a zero-width port, so the width is forced to `1` instead. For any `SIZE > 1` the expression reduces to `$clog2(SIZE)`.

### Dynamic word selection

```systemverilog
assign out_o = in_i[sel_i];
```

`sel_i` indexes the unpacked input array `in_i[0:SIZE-1]`, and the addressed `WIDTH`-bit word is driven straight onto `out_o`. Because `sel_i` is a signal rather than a constant, this is a *dynamic* index: it synthesizes to a `SIZE`-to-1 multiplexer whose data inputs are the array words and whose control is `sel_i`. There is no arithmetic and no width change — the output is a verbatim copy of the chosen word.

For the "choose together" case in the [Purpose](#purpose), the caller does the merging upstream: it concatenates the two values that must move as a unit into one `WIDTH`-bit array element, so selecting that single element selects the whole pair. No dedicated paired-select logic lives in this module.

Source: [mux_n.sv](../../rtl/mux_n.sv)
