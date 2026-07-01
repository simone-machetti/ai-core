---
type: module
title: Gate B N
description: Parameterized conditioning gate — pass / zero / two's-complement negate SIZE words under a shared 2-bit select.
resource: rtl/gate_b_n.sv
tags: [module, routing, gate]
timestamp: 2026-07-01
---

# Gate B N

`gate_b_n` — Parameterized conditioning gate: passes, zeros, or two's-complement-negates a group of `SIZE` `WIDTH`-bit words under a shared 2-bit select.

## Purpose

A 3-way mux per word — the input, an all-zero word, or the input's negation — for the operand that needs all three across the modes: pass, zeroing idle words, and sign negation. The select is shared by all `SIZE` words. Contrast [gate_a_n](gate_a_n.md), which only zeros.

## Parameters

| Parameter | Default | Description                             |
| --------- | ------- | --------------------------------------- |
| `WIDTH`   | 8       | Bit width of each word.                 |
| `SIZE`    | 4       | Number of words (all share the select). |

## Interface

| Signal  | Dir | Width            | Description                                                    |
| ------- | --- | ---------------- | -------------------------------------------------------------- |
| `in_i`  | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`.                     |
| `sel_i` | in  | 2                | Operation for all words: `0` = pass, `1` = zero, `2` = negate. |
| `out_o` | out | `SIZE` × `WIDTH` | Gated words — unpacked array `[0:SIZE-1]`.                     |

## Internal logic

Purely combinational, applied to each word `i` under the shared `sel_i`: `0` passes (`out_o[i] = in_i[i]`), `1` zeros (`out_o[i] = 0`), and `2` negates (`out_o[i] = -in_i[i]`, two's complement at the same `WIDTH`, so the most-negative value wraps). No clock, no storage.

## Instantiation

```systemverilog
gate_b_n #(.WIDTH(8), .SIZE(4)) gate_b_n_i (
    .in_i(in), .sel_i(sel), .out_o(out)
);
```

Source: [gate_b_n.sv](../../rtl/gate_b_n.sv)
