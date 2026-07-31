# Exponent Dispatch B (Square-BFP)

`disp_array_exp_b_sqr_bfp` — the B-exponent sideband dispatcher for the square-BFP grid: the exponent counterpart of [disp_array_b_sqr](./disp_array_b_sqr.md) and a near-copy of the baseline [disp_array_exp_b_bfp](./disp_array_exp_b_bfp.md), with the idle mask re-keyed to the square dispatcher's per-DP8 `zero_i`. One instance per grid column, next to the mantissa dispatcher it mirrors.

## Purpose

Like its A sibling [disp_array_exp_a_sqr_bfp](./disp_array_exp_a_sqr_bfp.md), this module routes the **exponent sideband** that pairs with [disp_array_b_sqr](./disp_array_b_sqr.md)'s mantissa dispatch, so each DP8 reaches [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) with its `e_B`. The difference from the A path is the **B granularity**: plane packing can put two 32-bit halves with *different* exponents in one 64-bit block, so B carries **two** 6-bit exponents per block — a 12-bit chunk. The dispatcher routes the 4 per-block chunks with the same 4→1 block select per pair, then applies the same fixed high/low split as the mantissa path: chunk bits `[11:6]` are the exponent of the block's **high** (H) half and go to the even DP8 (`2p`); bits `[5:0]` belong to the **low** (L) half and go to the odd DP8 (`2p+1`).

The only change from [disp_array_exp_b_bfp](./disp_array_exp_b_bfp.md) is the **idle mask**: the per-DP8 `zero_i[16]` that [disp_array_a_sqr](./disp_array_a_sqr.md) / [disp_array_b_sqr](./disp_array_b_sqr.md) use to zero an idle DP8 (modes 5/6), instead of the baseline per-pair `ctr_h_i`/`ctr_l_i` ZERO-decode. `zero_i[2p]` gates the H half, `zero_i[2p+1]` the L half. No `NEG`/`NEG_CARRY` handling — the complex-mode negate moved into [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) — so `zero_i` is a pure idle bit, no code decode.

**Why gate the exponent at all** — [disp_array_b_sqr](./disp_array_b_sqr.md) already zeroes an idle DP8's mantissa, but the exponent is an independent sideband; a zero-mantissa DP8 carrying a leftover `e_B` could win an [align_cell_bfp](./align_cell_bfp.md) exponent max and wrongly right-shift the active data. Forcing the idle exponent to 0 keeps it out of every max.

## Parameters

None — fixed to the PE configuration; all `localparam`s. `NUM_BLK = 4`, `EXP_WIDTH = 6`, `CHK_WIDTH = 2*EXP_WIDTH = 12` (the two-half chunk), `NUM_PAIR = 8`, `NUM_DP8 = 16`, `SEL_WIDTH = 2`. The registered exponent word is `NUM_BLK*CHK_WIDTH = 48`-bit.

## Interface

| Signal              | Dir | Width   | Description                                                                          |
| ------------------- | --- | ------- | ------------------------------------------------------------------------------------ |
| `clk_i` / `rst_ni`  | in  | 1       | Clock / async active-low reset.                                                     |
| `pe_exp_b_i`        | in  | 48      | Column B exponents — four 12-bit chunks (an H+L exponent pair per 64-bit block).    |
| `sel_b_i[0:7]`      | in  | 2 each  | Per-pair B-block select (4→1); the **same** select the mantissa dispatcher uses.    |
| `zero_i[0:15]`      | in  | 1 each  | **NEW** — per-DP8 idle zero (replaces the baseline `ctr_h_i`/`ctr_l_i` ZERO-decode). |
| `exp_b_dp8_o[0:15]` | out | 6 each  | Per-DP8 B exponent, idle-gated, broadcast to the column's PEs.                       |

## Instantiation

```systemverilog
disp_array_exp_b_sqr_bfp disp_array_exp_b_sqr_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .pe_exp_b_i(pe_exp_b),
    .sel_b_i(sel_b), .zero_i(zero_dp8), .exp_b_dp8_o(exp_b_dp8)
);
```

## Internal logic

Reshape into four 12-bit chunks, **register** (in step with [disp_array_b_sqr](./disp_array_b_sqr.md)'s 256-bit operand register), then per pair a 4→1 [mux_n](./mux_n.md) selects the chunk, the chunk is split into its H and L 6-bit exponents, and two [gate_n](./gate_n.md)s idle-mask them:

```systemverilog
mux_n #(.WIDTH(CHK_WIDTH), .SIZE(NUM_BLK)) mux_n_exp_i (
    .in_i(exp_blk_q), .sel_i(sel_b_i[p]), .out_o(exp_sel)
);
assign exp_split[0] = exp_sel[CHK_WIDTH-1:EXP_WIDTH];   // H half → even DP8
assign exp_split[1] = exp_sel[EXP_WIDTH-1:0];           // L half → odd  DP8
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_h_i ( .in_i(exp_split[0:0]), .sel_i(zero_i[2*p+0]), .out_o(exp_h) );
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_l_i ( .in_i(exp_split[1:1]), .sel_i(zero_i[2*p+1]), .out_o(exp_l) );
```

Unlike the A path — where both DP8s share the one block exponent — the B path hands each half its **own** exponent from the split, matching the mantissa dispatcher's fixed high/low int4 split. The dispatch is combinational; its output is broadcast to the column's PEs.

Diagram: [disp_array_exp_b_sqr_bfp](../../doc/diagrams/disp_array_exp_b_sqr_bfp.excalidraw).

Source: [disp_array_exp_b_sqr_bfp.sv](../../rtl/disp_array_exp_b_sqr_bfp.sv) — Diagram: [disp_array_exp_b_sqr_bfp](../../doc/diagrams/disp_array_exp_b_sqr_bfp.excalidraw)
