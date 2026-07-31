# Exponent Dispatch A (Square-BFP)

`disp_array_exp_a_sqr_bfp` — the A-exponent sideband dispatcher for the square-BFP grid: the exponent counterpart of [disp_array_a_sqr](./disp_array_a_sqr.md) and a near-copy of the baseline [disp_array_exp_a_bfp](./disp_array_exp_a_bfp.md), with the idle mask re-keyed to the square dispatcher's per-DP8 `zero_i`. One instance per grid row, next to the mantissa dispatcher it mirrors.

## Purpose

BFP carries the block scale as a **separate sideband**: while [disp_array_a_sqr](./disp_array_a_sqr.md) routes the mantissa nibbles, this module routes the matching **exponents** so each DP8 reaches [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) with its `e_A`. It takes the 4 per-block A format exponents — one 6-bit exponent per 64-bit A block (the source-format rule: one shared exponent per block) — and dispatches them to the 16 DP8s with the **same** 4→1 block select per pair as the mantissa path, then zeroes each half of a pair whose DP8 is idle.

The only change from [disp_array_exp_a_bfp](./disp_array_exp_a_bfp.md) is the **idle mask**. The baseline decodes idleness per pair from `ctr_h_i`/`ctr_l_i` (the multiply dispatcher's ZERO codes); the square variant reuses the per-DP8 `zero_i[16]` that [disp_array_a_sqr](./disp_array_a_sqr.md) / [disp_array_b_sqr](./disp_array_b_sqr.md) already use to force an idle DP8 to a real hardware zero (modes 5/6). `zero_i[2p]` gates the even DP8 (the H half), `zero_i[2p+1]` the odd DP8 (the L half). No `NEG`/`NEG_CARRY` handling is needed — the complex-mode negate moved into [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) — so `zero_i` is a **pure idle bit** with no code decode.

**Why gate the exponent at all** — even though [disp_array_a_sqr](./disp_array_a_sqr.md) already zeroes an idle DP8's mantissa, the exponent is an *independent* sideband. A zero-mantissa DP8 still carrying its leftover scale `e_A` could win an [align_cell_bfp](./align_cell_bfp.md) exponent max downstream and wrongly right-shift (truncate) the active data. Forcing the idle exponent to 0 keeps it out of every max.

## Parameters

None — fixed to the PE configuration; all `localparam`s. `NUM_BLK = 4` (A blocks), `EXP_WIDTH = 6` (one exponent), `NUM_PAIR = 8`, `NUM_DP8 = 16`, `SEL_WIDTH = $clog2(NUM_BLK) = 2`. The registered exponent word is `NUM_BLK*EXP_WIDTH = 24`-bit.

## Interface

| Signal              | Dir | Width   | Description                                                                          |
| ------------------- | --- | ------- | ------------------------------------------------------------------------------------ |
| `clk_i` / `rst_ni`  | in  | 1       | Clock / async active-low reset.                                                     |
| `pe_exp_a_i`        | in  | 24      | Row A exponents — four 6-bit per-block exponents.                                    |
| `sel_a_i[0:7]`      | in  | 2 each  | Per-pair A-block select (4→1); the **same** select the mantissa dispatcher uses.    |
| `zero_i[0:15]`      | in  | 1 each  | **NEW** — per-DP8 idle zero (replaces the baseline `ctr_h_i`/`ctr_l_i` ZERO-decode). |
| `exp_a_dp8_o[0:15]` | out | 6 each  | Per-DP8 A exponent, idle-gated, broadcast to the row's PEs.                          |

## Instantiation

```systemverilog
disp_array_exp_a_sqr_bfp disp_array_exp_a_sqr_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .pe_exp_a_i(pe_exp_a),
    .sel_a_i(sel_a), .zero_i(zero_dp8), .exp_a_dp8_o(exp_a_dp8)
);
```

## Internal logic

Reshape the 24-bit word into four 6-bit block exponents, **register** them (in step with the 256-bit operand register of [disp_array_a_sqr](./disp_array_a_sqr.md)), then per pair a combinational 4→1 [mux_n](./mux_n.md) selects the block and two [gate_n](./gate_n.md)s idle-mask the two halves:

```systemverilog
mux_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_BLK)) mux_n_exp_i (
    .in_i(exp_blk_q), .sel_i(sel_a_i[p]), .out_o(exp_sel)
);
assign exp_pair[0] = exp_sel;   // both DP8s of the pair share the A block exponent
assign exp_pair[1] = exp_sel;
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_h_i ( .in_i(exp_pair[0:0]), .sel_i(zero_i[2*p+0]), .out_o(exp_h) );
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_l_i ( .in_i(exp_pair[1:1]), .sel_i(zero_i[2*p+1]), .out_o(exp_l) );
```

Both DP8s of a pair share the one block exponent (the A source rule broadcasts a single scale per 64-bit block), so the per-DP8 `zero_i` is what lets one half idle while its sibling survives — the finer granularity the square modes 5/6 need. The dispatch is combinational; its output is broadcast to the row's PEs.

Diagram: [disp_array_exp_a_sqr_bfp](../../doc/diagrams/disp_array_exp_a_sqr_bfp.excalidraw).

Source: [disp_array_exp_a_sqr_bfp.sv](../../rtl/disp_array_exp_a_sqr_bfp.sv) — Diagram: [disp_array_exp_a_sqr_bfp](../../doc/diagrams/disp_array_exp_a_sqr_bfp.excalidraw)
