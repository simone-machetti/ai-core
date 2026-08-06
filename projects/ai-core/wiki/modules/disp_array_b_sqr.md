# Dispatch Array B (Square)

`disp_array_b_sqr` — the square variant of [disp_array_b](./disp_array_b.md). Same routing (register the 256-bit B operand, 4→1 block select per pair, high/low int4 split), but each half is **centered and idle-zeroed** by a per-DP8 [gate_b_n_sqr](./gate_b_n_sqr.md) instead of pass/zero/negated. One instance per grid column.

## Purpose

Like [disp_array_a_sqr](./disp_array_a_sqr.md) but for B: it centers each nibble at the dispatcher (shared with the column's PEs and its β generator) and idle-zeros whole DP8s. It **drops the complex-mode negate** that [disp_array_b](./disp_array_b.md) did — `gate_b_n`'s `GATE_NEG`/`GATE_NEG_CARRY` and the L→H carry chain are gone; that sign relocates into [pe_array_sqr](./pe_array_sqr.md). New inputs `is_signed_b_i[16]` and `zero_i[16]` come from [ctrl](./ctrl.md).

## Parameters

Same as [disp_array_b](./disp_array_b.md) (`NUM_BLK=4`, `BLK_WIDTH=64`, `NUM_PAIR=8`, `NUM_DP8=16`, `B_DP8_WIDTH=32`, `B_ELEM_WIDTH=4`, `NUM_B_ELEM=8`).

## Interface

| Signal                | Dir | Width   | Description                                         |
| --------------------- | --- | ------- | --------------------------------------------------- |
| `clk_i` / `rst_ni`    | in  | 1       | Clock / async active-low reset.                     |
| `pe_in_b_i`           | in  | 256     | Column B operand — four 64-bit blocks.              |
| `sel_b_i[0:7]`        | in  | 2 each  | Per-pair B-block select (4→1).                      |
| `is_signed_b_i[0:15]` | in  | 1 each  | **NEW** — per-DP8 B signedness (drives centering).  |
| `zero_i[0:15]`        | in  | 1 each  | **NEW** — per-DP8 idle zero.                        |
| `b_dp8_o[0:15]`       | out | 32 each | Centered/zeroed B per DP8, broadcast to the column. |

`ctr_l`/`ctr_h` and the carry ports are **removed** vs the baseline.

## Instantiation

```systemverilog
disp_array_b_sqr disp_array_b_sqr_i (
    .clk_i(clk_b), .rst_ni(rst_ni), .pe_in_b_i(in_b_i[c]),
    .sel_b_i(sel_b), .is_signed_b_i(is_signed_b), .zero_i(zero_i),
    .b_dp8_o(b_dp8_col[c])
);
```

## Internal logic

Reshape → register → per-pair 4→1 mux → high/low split (as in [disp_array_b](./disp_array_b.md)), then each half runs a [gate_b_n_sqr](./gate_b_n_sqr.md) — even DP8 `2p` = HIGH half, odd DP8 `2p+1` = LOW half — centered/zeroed per DP8:

```systemverilog
gate_b_n_sqr #(.WIDTH(B_ELEM_WIDTH), .SIZE(NUM_B_ELEM)) gate_b_n_sqr_h_i (
    .in_i(bhi_nib), .is_signed_i(is_signed_b_i[2*p+0]), .zero_i(zero_i[2*p+0]), .out_o(bhi_gated)
);
gate_b_n_sqr #(.WIDTH(B_ELEM_WIDTH), .SIZE(NUM_B_ELEM)) gate_b_n_sqr_l_i (
    .in_i(blo_nib), .is_signed_i(is_signed_b_i[2*p+1]), .zero_i(zero_i[2*p+1]), .out_o(blo_gated)
);
```

No carry plumbing (`blo_cin`/`blo_carry`) — with the negate gone there is nothing to chain.

Diagram: [disp_array_b_sqr](../../doc/diagrams/disp_array_b_sqr.excalidraw).

Source: [disp_array_b_sqr.sv](../../rtl/disp_array_b_sqr.sv) — Testbench: [tb_disp_array_sqr.sv](../../tb/tb_disp_array_sqr.sv)
