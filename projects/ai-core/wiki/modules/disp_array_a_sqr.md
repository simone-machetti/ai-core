# Dispatch Array A (Square)

`disp_array_a_sqr` — the square variant of [disp_array_a](./disp_array_a.md). Same routing (register the 256-bit A operand, one 4→1 block select per pair, broadcast to the pair), but each DP8 output is **centered and idle-zeroed** by a per-DP8 [gate_a_n_sqr](./gate_a_n_sqr.md) instead of passed raw. One instance per grid row.

## Purpose

The square datapath needs pre-centered nibbles, so `disp_array_a_sqr` folds the `−8` centering into the A dispatch (shared by the row's PEs and its α generator). It also gains a per-DP8 `zero_i`: the square PE cannot idle a lane by zeroing B alone (a centered `0` becomes `−8`, and `(a−8)² ≠ 0`), so idle DP8s zero **both** operands to a real hardware zero (modes 5/6). The two new inputs — per-DP8 `is_signed_a_i[16]` and `zero_i[16]` — come from [ctrl](./ctrl.md).

## Parameters

Same as [disp_array_a](./disp_array_a.md) (`NUM_BLK=4`, `BLK_WIDTH=64`, `NUM_PAIR=8`, `NUM_DP8=16`, `A_DP8_WIDTH=64`), plus `A_ELEM=8` / `NUM_A_ELEM=8` (int8 lanes per DP8).

## Interface

| Signal                | Dir | Width   | Description                                        |
| --------------------- | --- | ------- | -------------------------------------------------- |
| `clk_i` / `rst_ni`    | in  | 1       | Clock / async active-low reset.                    |
| `pe_in_a_i`           | in  | 256     | Row A operand — four 64-bit blocks.                |
| `sel_a_i[0:7]`        | in  | 2 each  | Per-pair A-block select (4→1).                     |
| `is_signed_a_i[0:15]` | in  | 1 each  | **NEW** — per-DP8 A signedness (drives centering). |
| `zero_i[0:15]`        | in  | 1 each  | **NEW** — per-DP8 idle zero.                       |
| `a_dp8_o[0:15]`       | out | 64 each | Centered/zeroed A per DP8, broadcast to the row.   |

## Instantiation

```systemverilog
disp_array_a_sqr disp_array_a_sqr_i (
    .clk_i(clk_a), .rst_ni(rst_ni), .pe_in_a_i(in_a_i[r]),
    .sel_a_i(sel_a), .is_signed_a_i(is_signed_a), .zero_i(zero_i),
    .a_dp8_o(a_dp8_row[r])
);
```

## Internal logic

Reshape → register → per-pair 4→1 mux (as in [disp_array_a](./disp_array_a.md)), then — instead of broadcasting `a_sel` raw — each of the pair's two DP8s runs its own [gate_a_n_sqr](./gate_a_n_sqr.md), so it can be centered/zeroed independently (mode 5 idles one DP8 of *every* pair, so the gates are per-DP8, 16 in all):

```systemverilog
for (genvar e = 0; e < NUM_A_ELEM; e++)          // split a_sel into 8 int8 lanes
    assign a_lane[e] = a_sel[e*A_ELEM +: A_ELEM];

for (d = 0; d < 2; d++) begin : gen_dp8
    gate_a_n_sqr #(.WIDTH(A_ELEM), .SIZE(NUM_A_ELEM)) gate_a_n_sqr_i (
        .in_i(a_lane), .is_signed_i(is_signed_a_i[2*p+d]),
        .zero_i(zero_i[2*p+d]), .out_o(o_lane)
    );
    // pack o_lane back into a_dp8_o[2*p+d]
end
```

Diagram: [disp_array_a_sqr](../../doc/diagrams/disp_array_a_sqr.excalidraw).

Source: [disp_array_a_sqr.sv](../../rtl/disp_array_a_sqr.sv) — Testbench: [tb_disp_array_sqr.sv](../../tb/tb_disp_array_sqr.sv)
