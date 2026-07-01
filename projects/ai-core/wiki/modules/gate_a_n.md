---
type: module
title: Gate A N
description: Parameterized zero gate — passes or forces to zero SIZE WIDTH-bit words under a shared 1-bit select.
resource: rtl/gate_a_n.sv
tags: [module, routing, gate]
timestamp: 2026-07-01
---

# Gate A N

`gate_a_n` — Parameterized zero gate: passes or forces to zero a group of `SIZE` `WIDTH`-bit words under a shared 1-bit select.

## Purpose

Conditionally masks a group of words to zero — the gating that only ever needs zeroing, never negation (contrast [gate_b_n](gate_b_n.md)). At `WIDTH = 1` the same cell serves as a carry enable.

## Parameters

| Parameter | Default | Description                             |
| --------- | ------- | --------------------------------------- |
| `WIDTH`   | 8       | Bit width of each word.                 |
| `SIZE`    | 4       | Number of words (all share the select). |

## Interface

| Signal  | Dir | Width            | Description                                |
| ------- | --- | ---------------- | ------------------------------------------ |
| `in_i`  | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`. |
| `sel_i` | in  | 1                | `0` = pass, `1` = zero.                    |
| `out_o` | out | `SIZE` × `WIDTH` | Gated words — unpacked array `[0:SIZE-1]`. |

## Internal logic

Purely combinational, per word `i` under the shared `sel_i`: `out_o[i] = sel_i ? 0 : in_i[i]`. No clock, no storage.

## Instantiation

```systemverilog
gate_a_n #(.WIDTH(8), .SIZE(4)) gate_a_n_i (
    .in_i(in), .sel_i(sel), .out_o(out)
);
```

Source: [gate_a_n.sv](../../rtl/gate_a_n.sv)
