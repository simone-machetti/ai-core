---
type: module
title: Shifter N
description: Parameterized conditional left shifter — optionally shifts each of SIZE words left by SHIFT, widening to WIDTH+SHIFT.
resource: rtl/shift_n.sv
tags: [module, routing, shifter]
timestamp: 2026-07-01
---

# Shifter N

`shift_n` — Parameterized conditional left shifter: optionally shifts each of `SIZE` `WIDTH`-bit inputs left by `SHIFT`, widening the output to `WIDTH + SHIFT` bits so the shifted value is never truncated.

## Purpose

Applies a programmable power-of-two weight (`2^SHIFT`) to a group of values, or passes them through unchanged, under a single shared select — the per-level weighting step of a reduction tree.

## Parameters

| Parameter | Default | Description                                    |
| --------- | ------- | ---------------------------------------------- |
| `WIDTH`     | 8     | Bit width of each input word.                  |
| `SIZE`      | 4     | Number of input words (all share the selects). |
| `SHIFT`     | 4     | Left-shift amount applied when selected.       |
| `IS_SIGNED` | 1     | Pass-through extension: `1` = sign-extend, `0` = zero-extend. |

`OUT_WIDTH` (derived) `= WIDTH + SHIFT`.

## Interface

| Signal        | Dir | Width                | Description                                                   |
| ------------- | --- | -------------------- | ------------------------------------------------------------- |
| `in_i`        | in  | `SIZE` × `WIDTH`     | Input words — unpacked array `[0:SIZE-1]`.                    |
| `sel_i`       | in  | 1                    | `1` = shift left by `SHIFT`; `0` = pass through.              |
| `out_o`       | out | `SIZE` × `OUT_WIDTH` | Result words — unpacked array `[0:SIZE-1]`.                   |

## Internal logic

Purely combinational, applied independently to each input `i` (all sharing `sel_i`). When `sel_i = 1` the output is `{in_i[i], SHIFT zeros}` — the value multiplied by `2^SHIFT`, filling the full `OUT_WIDTH` with no loss, independent of `IS_SIGNED`. When `sel_i = 0` the output is `in_i[i]` extended to `OUT_WIDTH` — sign-extended when `IS_SIGNED`, otherwise zero-extended. Signedness is a compile-time parameter because a shifter's datapath position fixes it (same rationale as `cpr_w_n`).

## Instantiation

```systemverilog
shift_n #(.WIDTH(8), .SIZE(4), .SHIFT(4), .IS_SIGNED(1'b1)) shift_n_i (
    .in_i(in), .sel_i(sel), .out_o(out)
);
```

Source: [shift_n.sv](../../rtl/shift_n.sv)
