---
type: module
title: Adder N
description: Parameterized two-input adder with a WIDTH+1 result so the sum never overflows.
resource: rtl/add_n.sv
tags: [module, arithmetic, adder]
timestamp: 2026-07-01
---

# Adder N

`add_n` — Parameterized two-input adder producing a `WIDTH + 1`-bit result so the sum never overflows.

## Purpose

Adds two `WIDTH`-bit operands into a `WIDTH + 1`-bit result, the extra bit holding the carry or overflow.

## Parameters

| Parameter | Default | Description                |
| --------- | ------- | -------------------------- |
| `WIDTH`   | 8       | Bit width of each operand. |

`OUT_WIDTH` (derived) `= WIDTH + 1`.

## Interface

| Signal        | Dir | Width       | Description                                                       |
| ------------- | --- | ----------- | ----------------------------------------------------------------- |
| `in_0_i`      | in  | `WIDTH`     | First operand.                                                    |
| `in_1_i`      | in  | `WIDTH`     | Second operand.                                                   |
| `is_signed_i` | in  | 1           | `1` = signed (sign-extended) add; `0` = unsigned (zero-extended). |
| `out_o`       | out | `OUT_WIDTH` | Sum `in_0_i + in_1_i`, with no overflow.                          |

## Internal logic

Purely combinational: both operands are extended to `OUT_WIDTH` — sign-extended when `is_signed_i`, otherwise zero-extended — and added. The low `WIDTH` bits of `out_o` are identical in both modes; only the most-significant (overflow) bit differs.

## Instantiation

```systemverilog
add_n #(.WIDTH(8)) add_n_i (
    .in_0_i(a), .in_1_i(b), .is_signed_i(is_signed), .out_o(sum)
);
```

Source: [add_n.sv](../../rtl/add_n.sv)
