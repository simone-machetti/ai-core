---
type: module
title: Full Adder
description: One-bit full adder — the 3:2 cell inside the carry-save compressors.
resource: rtl/fa.sv
tags: [module, arithmetic, full-adder, carry-save]
timestamp: 2026-07-01
---

# Full Adder

`fa` — One-bit full adder: sums three input bits into a sum bit and a carry-out bit.

## Purpose

The 3:2 building block of the carry-save compressors [cpr_c_n](cpr_c_n.md) and [cpr_w_n](cpr_w_n.md) — adds three single-bit inputs and produces their two-bit result as a sum bit (weight 1) and a carry-out bit (weight 2). Reused from `ai-core-legacy`.

## Interface

| Signal   | Dir | Width | Description        |
| -------- | --- | ----- | ------------------ |
| `in_0_i` | in  | 1     | First addend bit.  |
| `in_1_i` | in  | 1     | Second addend bit. |
| `cin_i`  | in  | 1     | Carry-in bit.      |
| `sum_o`  | out | 1     | Sum bit.           |
| `cout_o` | out | 1     | Carry-out bit.     |

## Internal logic

Purely combinational: `sum_o = in_0_i ^ in_1_i ^ cin_i`, and `cout_o = (in_0_i & in_1_i) | (cin_i & in_0_i) | (cin_i & in_1_i)` — the majority of the three inputs. No clock, no storage.

## Instantiation

```systemverilog
fa fa_i (
    .in_0_i(a), .in_1_i(b), .cin_i(cin), .sum_o(sum), .cout_o(cout)
);
```

Source: [fa.sv](../../rtl/fa.sv)
