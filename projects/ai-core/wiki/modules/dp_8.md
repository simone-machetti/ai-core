---
type: module
title: Dot Product 8
description: DP8 (8×4) dot-product core with per-operand signedness — eight int8×int4 MACs in carry-save.
resource: rtl/dp_8.sv
tags: [module, arithmetic, dot-product, dp8, carry-save]
timestamp: 2026-07-01
---

# Dot Product 8

`dp_8` — DP8 (8×4) dot-product core with per-operand signedness: computes `Σ_{k=0..7} a_k · b_k` over eight `int8 × int4` products and returns it in carry-save form (`sum_o`, `carry_o`).

## Purpose

Computes the length-8 dot product of eight `int8 × int4` products and returns it in carry-save form, leaving the carry-propagate resolve to the downstream `pe_array` tree and `acc_array`. It is fixed to the PE configuration — 8 lanes, 8-bit multiplicand `a`, 4-bit multiplier `b`, no parameters — and hand-sized to the minimum width for that size, while the leaf primitives it uses stay general. The `pe_array` instantiates 16 of these. See the diagram companion at [doc/diagrams/dp_8.md](../../doc/diagrams/dp_8.md).

`a` and `b` are signed or unsigned independently (`is_signed_a_i` / `is_signed_b_i`), because the operating modes require it: an operand field's high half is signed and its low half unsigned — for both `a` and `b` — so all four sign combinations occur across the 16 DP8s.

## Interface

| Signal          | Dir | Width  | Description                                                  |
| --------------- | --- | ------ | ------------------------------------------------------------ |
| `a_i[0:7]`      | in  | 8 each | Multiplicand elements (`int8`).                              |
| `b_i[0:7]`      | in  | 4 each | Multiplier elements (`int4`), radix-4 Booth-recoded.         |
| `is_signed_a_i` | in  | 1      | Multiplicand (`a`) signedness: `1` = signed, `0` = unsigned. |
| `is_signed_b_i` | in  | 1      | Multiplier (`b`) signedness: `1` = signed, `0` = unsigned.   |
| `sum_o`         | out | 18     | Carry-save sum row.                                          |
| `carry_o`       | out | 18     | Carry-save carry row; `sum_o + carry_o` = `Σ a_k·b_k`.       |

## Internal logic

Three combinational stages, carry-save throughout. First, eight radix-4 Booth generators [booth_r4](booth_r4.md), one per lane, each produce `PP_SIZE = 3` partial products (weights `2^0`, `2^2`, `2^4`); the weight-`2^4` product is the extra Booth term an unsigned `b` needs, and is `0` when `b` is signed. Second, for each of the three weights one 8:2 Wallace compressor [cpr_w_n](cpr_w_n.md) reduces the eight same-weight partial products across the lanes to a carry-save pair. Third, each weight's pair is sign-extended and shifted to its position (`<< 0/2/4`) and a final 6:2 compressor [cpr_w_n](cpr_w_n.md) reduces the six aligned rows to the two carry-save outputs. Each carry-save pair carries one guard bit so it stays sign-consistent, which lets the pairs be re-aligned and lets `pe_array` sign-extend the output. Fully carry-save — no resolve adder.

## Bit widths

| Stage                          | Width | Composition                          |
| ------------------------------ | ----- | ------------------------------------ |
| Booth partial product          | 10    | `int8 · {0,±1,±2}` — exact range.    |
| Per-weight sum (CPR 8:2, ×3)    | 14    | 13-bit sum-of-8 range + 1 guard bit. |
| Weight-`2^4` aligned (`<< 4`)   | 18    | 14-bit row shifted `<< 4`.           |
| Dot product (CPR 6:2, output)   | 18    | holds the 16-bit dot range + guard.  |

The dot product spans a 16-bit signed range `[−16320, +30600]` — the `u×u` corner `8·255·15 = 30600` and the `u×s` corner `8·255·(−8) = −16320`. The final 6:2 compressor takes no width growth (`OUT_WIDTH = FINAL_IN`); the 18-bit output width is set by the weight-`2^4` aligned rows.

## Instantiation

```systemverilog
dp_8 dp_8_i (
    .a_i(a), .b_i(b),
    .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
    .sum_o(sum), .carry_o(carry)
);
```

Source: [dp_8.sv](../../rtl/dp_8.sv) — Testbench: [tb_dp_8.sv](../../tb/tb_dp_8.sv)
