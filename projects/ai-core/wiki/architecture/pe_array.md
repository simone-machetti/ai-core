---
type: architecture
title: PE Array
description: The 16-DP8 carry-save reduction tree — computes the 16 DP8 dot products and reduces them through a 4-level shift/compress tree, exposing a carry-save tap at every level.
resource: rtl/pe_array.sv
tags: [architecture, reduction, tree, carry-save, pe]
timestamp: 2026-07-02
---

# PE Array

`pe_array` — instantiates the 16 [DP8](../modules/dp_8.md) cores and reduces their carry-save outputs through a 4-level tree with programmable per-level shifts, exposing a carry-save tap at every level so a mode reads its results at the depth matching its output count.

## Purpose

Each DP8 produces one length-8 dot product in 17-bit carry-save form; the tree sums those 16 partial results with the per-mode radix weights and leaves the result in carry-save for the accumulator to resolve. A mode's outputs appear at the tree level whose node count matches the number of parallel results: 8 results at L0, 4 at L1, 2 at L2, 1 at L3. The 16 DP8s live here, so their per-lane signedness (`is_signed_a`/`is_signed_b`) arrives from `pe_ctrl` and is wired straight to them; the routed operands arrive from the [dispatch array](disp_array.md).

## Interface

| Signal                 | Dir | Width   | Description                                                             |
| ---------------------- | --- | ------- | ----------------------------------------------------------------------- |
| `clk_i`                | in  | 1       | Clock.                                                                  |
| `rst_ni`               | in  | 1       | Asynchronous active-low reset.                                          |
| `a_dp8_i[0:15]`        | in  | 64 each | A operand per DP8 (8 × int8), from `disp_array`.                        |
| `b_dp8_i[0:15]`        | in  | 32 each | B operand per DP8 (8 × int4), from `disp_array`.                        |
| `is_signed_a_i[0:15]`  | in  | 1 each  | Per-DP8 multiplicand signedness, from `pe_ctrl`.                        |
| `is_signed_b_i[0:15]`  | in  | 1 each  | Per-DP8 multiplier signedness, from `pe_ctrl`.                          |
| `sel_shift_i[2:0]`     | in  | 1 each  | Per-level shift enable: `[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`. |
| `l0_sum_o`/`l0_carry_o[0:7]` | out | 17 each | L0 taps (carry-save).                                            |
| `l1_sum_o`/`l1_carry_o[0:3]` | out | 29 each | L1 taps.                                                         |
| `l2_sum_o`/`l2_carry_o[0:1]` | out | 37 each | L2 taps.                                                         |
| `l3_sum_o`/`l3_carry_o`      | out | 39      | L3 tap.                                                          |

## Internal logic

The 16 [DP8](../modules/dp_8.md) cores feed a balanced binary tree of 15 [4:2 compressors](../modules/cpr_w_n.md) (8 + 4 + 2 + 1). Each node merges two carry-save operands: the higher-weight one passes through a [shifter](../modules/shift_n.md) (left-shifted by the level amount when its `sel_shift` bit is set, otherwise sign-extended), the other through an [extender](../modules/ext_n.md) that widens it to match, and the four rows compress back to two — everything signed (`IS_SIGNED = 1`). L0 combines a **crossed** DP8 pair (`l0[2g] = dp8[4g] + dp8[4g+2]`, `l0[2g+1] = dp8[4g+1] + dp8[4g+3]`), so a node mixes DP8s from two different `disp_array` pairs, with the lower DP8 index — the higher-weight field — as the shifted operand; L0 is the only registered stage. L1, L2, and L3 then combine adjacent nodes straight-binary (`l1[j] = l0[2j] + l0[2j+1]`, and so on) combinationally. The per-level shift amounts are `8`, `4`, `8`, and the enables follow the operand split — L0 shifts when A is 16-bit, L1 when B is at least 8-bit, L2 when B is 16-bit — which reproduces the `2^0…2^20` field weights in `modes.xlsx`. Widths grow as `17 (DP8) + shift + EXT` with `EXT = [0, 1, 0, 1]`, giving node widths `25 / 30 / 38 / 39`; each tap is the low slice that holds the modes reading that level (their value plus one guard bit), `17 / 29 / 37 / 39`, while the wider node bits feed the next level. Taps stay carry-save; the accumulator resolves and splits them into its 20-bit lanes.

## Instantiation

```systemverilog
pe_array pe_array_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .b_dp8_i(b_dp8),
    .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
    .sel_shift_i(sel_shift),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry),
    .l1_sum_o(l1_sum), .l1_carry_o(l1_carry),
    .l2_sum_o(l2_sum), .l2_carry_o(l2_carry),
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry)
);
```

Source: [pe_array.sv](../../rtl/pe_array.sv) — Testbench: [tb_pe_array.sv](../../tb/tb_pe_array.sv) — Diagram: [pe_array](../../doc/diagrams/pe_array.md)
