# Dispatch Array A

`disp_array_a` — the A half of the operand dispatch. It registers the 256-bit A operand and routes it to the 16 [dp_8](./dp_8.md) cores using one 4→1 block select per pair, with no crossbar. **One instance is shared by a whole grid row**: it dispatches `in_a[r]` once and broadcasts the result to every [pe](./pe.md) in that row.

## Purpose

The A and B operand paths are fully independent, so the old unified dispatch array split cleanly into `disp_array_a` (this module, A-path) and [disp_array_b](./disp_array_b.md) (B-path). Turning the 256-bit A operand — four 64-bit blocks — into the 16 per-DP8 A operands needs only a per-pair block select: the 16 DP8s form 8 pairs, and each pair reads exactly one A block (the dispatch rule from `modes.xlsx`), which feeds **both** DP8s of the pair unchanged. It is **data-path only**: operand signedness is a mode-decode control that [ctrl](./ctrl.md) sends straight to the DP8s. A is never gated here — a lane is idled by zeroing its B (`a·0 = 0`), so all gating lives on the B path.

## Parameters

**None — fixed to the PE configuration.** All sizing is `localparam`. The key locals:

| Localparam    | Value | Meaning                                      |
| ------------- | ----- | -------------------------------------------- |
| `NUM_BLK`     | 4     | 64-bit blocks per 256-bit operand.           |
| `BLK_WIDTH`   | 64    | Bit width of one operand block.              |
| `NUM_PAIR`    | 8     | DP8 pairs (each pair = two adjacent DP8s).   |
| `NUM_DP8`     | 16    | Total DP8 cores (`2 × NUM_PAIR`).            |
| `SEL_WIDTH`   | 2     | Block-select width, `$clog2(NUM_BLK)`.       |
| `A_DP8_WIDTH` | 64    | A operand per DP8 (`= BLK_WIDTH`, 8 × int8). |

## Interface

| Signal          | Dir | Width   | Description                                                               |
| --------------- | --- | ------- | ------------------------------------------------------------------------- |
| `clk_i`         | in  | 1       | Clock (gated per row by the row's ICG).                                   |
| `rst_ni`        | in  | 1       | Asynchronous active-low reset.                                            |
| `pe_in_a_i`     | in  | 256     | Operand A for this row — four 64-bit blocks (block `b` = `[b*64 +: 64]`). |
| `sel_a_i[0:7]`  | in  | 2 each  | Per-pair A-block select (4→1), from `ctrl`.                               |
| `a_dp8_o[0:15]` | out | 64 each | A operand per DP8 (8 × int8), broadcast to the row's PEs.                 |

## Instantiation

```systemverilog
disp_array_a disp_array_a_i (
    .clk_i    (clk_a),        // row-gated clock
    .rst_ni   (rst_ni),
    .pe_in_a_i(in_a_i[r]),    // 256-bit A operand for row r
    .sel_a_i  (sel_a),        // [0:7] per-pair A-block select
    .a_dp8_o  (a_dp8_row[r])  // [0:15] A per DP8 (64b), broadcast to the row
);
```

## Internal logic

Read top-to-bottom it is: reshape → register → per-pair A mux → duplicate onto the pair. There is no state past the input register, so the dispatch itself is combinational and its output is broadcast to the row's PEs.

### Input registering & block reshape

The operand arrives as a flat 256-bit bus. A first generate loop slices it into `NUM_BLK` = 4 unpacked 64-bit blocks (block `b` occupies bits `[b*64 +: 64]`), which a [reg_n](./reg_n.md) bank then latches — `SIZE = NUM_BLK` registers of `WIDTH = BLK_WIDTH` bits:

```systemverilog
for (b = 0; b < NUM_BLK; b++) begin : gen_reshape
    assign a_blk[b] = pe_in_a_i[b*BLK_WIDTH +: BLK_WIDTH];
end
reg_n #(.WIDTH(BLK_WIDTH), .SIZE(NUM_BLK)) reg_n_a_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(a_blk), .q_o(a_blk_q)
);
```

Everything downstream reads the registered blocks `a_blk_q`, so the operand is captured once and the dispatch is a combinational fan-out of that single registered copy.

### Per-pair A mux

Inside the `gen_pair` loop, one entry per pair `p` (0..7), a 4→1 [mux_n](./mux_n.md) over the four registered A blocks picks the single A block this pair uses, indexed by `sel_a_i[p]`, and that block feeds both DP8s of the pair:

```systemverilog
mux_n #(.WIDTH(BLK_WIDTH), .SIZE(NUM_BLK)) mux_n_a_i (
    .in_i(a_blk_q), .sel_i(sel_a_i[p]), .out_o(a_sel)
);
assign a_dp8_o[2*p+0] = a_sel;
assign a_dp8_o[2*p+1] = a_sel;
```

`a_dp8_o[2p]` and `a_dp8_o[2p+1]` are the same 64-bit value (8 × int8) — A passes straight from the mux to the two outputs. The per-mode `sel_a` vector is exactly the `modes.xlsx` dispatch map and doubles as the reference for `ctrl`.

Source: [disp_array_a.sv](../../rtl/disp_array_a.sv) — Testbench: [tb_disp_array.sv](../../tb/tb_disp_array.sv)
