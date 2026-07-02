---
type: architecture
title: Dispatch Array
description: Operand router — dispatches the two 256-bit PE operands to the 16 DP8s via per-pair 4->1 block selects, a B high/low split, and per-DP8 B gating.
resource: rtl/disp_array.sv
tags: [architecture, dispatch, routing, pe]
timestamp: 2026-07-02
---

# Dispatch Array

`disp_array` — operand-dispatch array: routes the two 256-bit PE operands (`pe_in_a_i`, `pe_in_b_i`) to the 16 [DP8](../modules/dp_8.md) cores using one 4→1 block select per operand per pair, a fixed B high/low split, and per-DP8 B gating.

## Purpose

Turns the two 256-bit operands — each four 64-bit blocks — into the 16 per-DP8 operand pairs the array needs, without a full crossbar: the 16 DP8s form 8 pairs, and each pair reads exactly one A block and one B block (the dispatch rule from `modes.xlsx`). It is data-path only — operand signedness (`is_signed_a`/`is_signed_b` per DP8) is a mode-decode control that `pe_ctrl` sends straight to the DP8s, not routed here. Fixed to the PE configuration; it instantiates the parameterized primitives.

## Interface

| Signal          | Dir | Width   | Description                                                     |
| --------------- | --- | ------- | --------------------------------------------------------------- |
| `clk_i`         | in  | 1       | Clock.                                                          |
| `rst_ni`        | in  | 1       | Asynchronous active-low reset.                                  |
| `pe_in_a_i`     | in  | 256     | Operand A — four 64-bit blocks (block `b` = `[b*64 +: 64]`).    |
| `pe_in_b_i`     | in  | 256     | Operand B — four 64-bit blocks.                                 |
| `sel_a_i[0:7]`  | in  | 2 each  | Per-pair A-block select (4→1).                                  |
| `sel_b_i[0:7]`  | in  | 2 each  | Per-pair B-block select (4→1).                                  |
| `ctr_l_i[0:7]`  | in  | 2 each  | Odd-DP8 (2p+1, low L) B gate: `0` pass, `1` zero, `2` negate.   |
| `ctr_h_i[0:7]`  | in  | 2 each  | Even-DP8 (2p, high H) B gate: `0` pass, `1` zero, `2` negate.   |
| `a_dp8_o[0:15]` | out | 64 each | A operand per DP8 (8 × int8).                                   |
| `b_dp8_o[0:15]` | out | 32 each | B operand per DP8 (8 × int4).                                   |

## Internal logic

The two 256-bit operands are latched on input by two [register banks](../modules/reg_n.md) (4 × 64-bit each). For each of the 8 pairs `p`: a 4→1 [multiplexer](../modules/mux_n.md) picks one A block, which feeds **both** DP8s of the pair (`a_dp8_o[2p]` = `a_dp8_o[2p+1]`); a second 4→1 multiplexer picks one B block, whose **high 32 bits (H)** go to the even DP8 (`2p`) and **low 32 bits (L)** to the odd DP8 (`2p+1`) — matching the dispatch, where the even lane carries the high nibble; each B half then passes through a [gate](../modules/gate_b_n.md) that, per int4 element, passes, zeros (idle lane), or two's-complement-negates (complex-mode imaginary term), selected by `ctr_h_i[p]` (even/H) / `ctr_l_i[p]` (odd/L). The dispatch is combinational after the input registers. Idling a lane is done by zeroing its B (`a·0 = 0`), so no A gate is needed. The per-mode control vectors (`sel_a`/`sel_b`/`ctr_*`) are exactly the `modes.xlsx` dispatch map and double as the reference for `pe_ctrl`.

## Instantiation

```systemverilog
disp_array disp_array_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .pe_in_a_i(pe_in_a), .pe_in_b_i(pe_in_b),
    .sel_a_i(sel_a), .sel_b_i(sel_b),
    .ctr_l_i(ctr_l), .ctr_h_i(ctr_h),
    .a_dp8_o(a_dp8), .b_dp8_o(b_dp8)
);
```

Source: [disp_array.sv](../../rtl/disp_array.sv) — Testbench: [tb_disp_array.sv](../../tb/tb_disp_array.sv) — Diagram: [disp_array](../../doc/diagrams/disp_array.md)
