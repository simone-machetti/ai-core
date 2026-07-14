# Dispatch Array B

`disp_array_b` — the B half of the operand dispatch. It registers the 256-bit B operand and routes it to the 16 [dp_8](./dp_8.md) cores using one 4→1 block select per pair, a fixed B high/low split, and per-DP8 B gating (pass / zero / negate). **One instance is shared by a whole grid column**: it dispatches `in_b[c]` once and broadcasts the result to every [pe](./pe.md) in that column.

## Purpose

The A and B operand paths are fully independent, so the old unified dispatch array split cleanly into [disp_array_a](./disp_array_a.md) (A-path) and `disp_array_b` (this module, B-path). The B path carries all the operand conditioning: after a per-pair 4→1 block select, the 64-bit B block is split into two 32-bit halves and each half is gated per int4 element — **pass** (most modes), **zero** (idle a DP8), or **negate** (the imaginary-B term in the complex modes). The block selects and gate ops (`sel_b`/`ctr_l`/`ctr_h`) come from [ctrl](./ctrl.md); this module owns the routing, split, and gate logic.

## Parameters

**None — fixed to the PE configuration.** All sizing is `localparam`. The key locals:

| Localparam     | Value | Meaning                                                        |
| -------------- | ----- | -------------------------------------------------------------- |
| `NUM_BLK`      | 4     | 64-bit blocks per 256-bit operand.                             |
| `BLK_WIDTH`    | 64    | Bit width of one operand block.                                |
| `NUM_PAIR`     | 8     | DP8 pairs (each pair = two adjacent DP8s).                     |
| `NUM_DP8`      | 16    | Total DP8 cores (`2 × NUM_PAIR`).                              |
| `SEL_WIDTH`    | 2     | Block-select width, `$clog2(NUM_BLK)`.                         |
| `B_DP8_WIDTH`  | 32    | B operand per DP8 (`= BLK_WIDTH/2`, 8 × int4).                 |
| `B_ELEM_WIDTH` | 4     | One B element (int4 nibble).                                   |
| `NUM_B_ELEM`   | 8     | int4 elements in a 32-bit B half (`B_DP8_WIDTH/B_ELEM_WIDTH`). |
| `OP_WIDTH`     | 2     | Width of a per-lane B-gate op code.                            |

## Interface

| Signal          | Dir | Width   | Description                                                                          |
| --------------- | --- | ------- | ------------------------------------------------------------------------------------ |
| `clk_i`         | in  | 1       | Clock (gated per column by the column's ICG).                                        |
| `rst_ni`        | in  | 1       | Asynchronous active-low reset.                                                       |
| `pe_in_b_i`     | in  | 256     | Operand B for this column — four 64-bit blocks.                                      |
| `sel_b_i[0:7]`  | in  | 2 each  | Per-pair B-block select (4→1), from `ctrl`.                                          |
| `ctr_l_i[0:7]`  | in  | 2 each  | Odd-DP8 (`2p+1`, low L) B-gate op: `0` pass, `1` zero, `2` negate, `3` negate-carry. |
| `ctr_h_i[0:7]`  | in  | 2 each  | Even-DP8 (`2p`, high H) B-gate op: `0` pass, `1` zero, `2` negate, `3` negate-carry. |
| `b_dp8_o[0:15]` | out | 32 each | B operand per DP8 (8 × int4), broadcast to the column's PEs.                          |

## Instantiation

```systemverilog
disp_array_b disp_array_b_i (
    .clk_i    (clk_b),        // column-gated clock
    .rst_ni   (rst_ni),
    .pe_in_b_i(in_b_i[c]),    // 256-bit B operand for column c
    .sel_b_i  (sel_b),        // [0:7] per-pair B-block select
    .ctr_l_i  (ctr_l),        // [0:7] odd-DP8  (low  half) B-gate op
    .ctr_h_i  (ctr_h),        // [0:7] even-DP8 (high half) B-gate op
    .b_dp8_o  (b_dp8_col[c])  // [0:15] B per DP8 (32b), broadcast to the column
);
```

## Internal logic

Read top-to-bottom it is: reshape → register → per-pair B mux → split → gate → pack. There is no state past the input register, so the dispatch itself is combinational and its output is broadcast to the column's PEs.

### Input registering & block reshape

The operand arrives as a flat 256-bit bus, sliced into four 64-bit blocks and latched by a [reg_n](./reg_n.md) bank (`SIZE = NUM_BLK`, `WIDTH = BLK_WIDTH`); everything downstream reads the registered blocks `b_blk_q`:

```systemverilog
for (b = 0; b < NUM_BLK; b++) begin : gen_reshape
    assign b_blk[b] = pe_in_b_i[b*BLK_WIDTH +: BLK_WIDTH];
end
reg_n #(.WIDTH(BLK_WIDTH), .SIZE(NUM_BLK)) reg_n_b_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(b_blk), .q_o(b_blk_q)
);
```

### Per-pair B mux + high/low split

Inside the `gen_pair` loop a 4→1 [mux_n](./mux_n.md) over the four registered B blocks picks this pair's B block under `sel_b_i[p]`. The 64-bit block is two 32-bit halves, each holding `NUM_B_ELEM` = 8 int4 nibbles. The **low** half (`b_sel[31:0]`) is destined for the odd DP8, the **high** half (`b_sel[63:32]`) for the even DP8. A small loop splits both halves into per-element nibbles and ties the low gate's carry-in to zero:

```systemverilog
for (e = 0; e < NUM_B_ELEM; e++) begin : gen_split
    assign blo_nib[e] = b_sel[e*B_ELEM_WIDTH +: B_ELEM_WIDTH];               // low  half nibble e
    assign bhi_nib[e] = b_sel[B_DP8_WIDTH + e*B_ELEM_WIDTH +: B_ELEM_WIDTH]; // high half nibble e
    assign blo_cin[e] = 1'b0;
end
```

An int8 B element `e` is `{bhi_nib[e], blo_nib[e]}`, its two halves living in the two different DP8s of the pair.

### B gating (pass / zero / negate)

Each 32-bit B half passes through its own [gate_b_n](./gate_b_n.md) — 8 nibbles, all sharing one op code. The **low** half is gated by `ctr_l_i[p]`, the **high** half by `ctr_h_i[p]`:

```systemverilog
gate_b_n #(.WIDTH(B_ELEM_WIDTH), .SIZE(NUM_B_ELEM)) gate_b_n_l_i (
    .in_i(blo_nib), .carry_i(blo_cin), .sel_i(ctr_l_i[p]),
    .out_o(blo_gated), .carry_o(blo_carry)
);
gate_b_n #(.WIDTH(B_ELEM_WIDTH), .SIZE(NUM_B_ELEM)) gate_b_n_h_i (
    .in_i(bhi_nib), .carry_i(blo_carry), .sel_i(ctr_h_i[p]),
    .out_o(bhi_gated), .carry_o()  /* unused at the top of the chain */
);
```

Per int4 element a gate can **pass** (`0`, most modes), **zero** (`1`, idle DP8 — e.g. mode 6), or **negate** (`2`, two's-complement, the imaginary-B term in the complex modes). Because a lane is idled by zeroing its B, no A gate is needed — this is why all gating is on the B path.

### Carry-chained negate for int8

A single int4 negate is exact on its own 4 bits, but an **int8** B element is split across the two gates, and two's-complement negation is `~x + 1`, whose `+1` must ripple as one carry from the least-significant nibble upward. `gate_b_n` exposes a per-element `carry_o` on `GATE_NEG` (`2`) and a fourth op `GATE_NEG_CARRY` (`3`) that adds the incoming `carry_i` in place of the fixed `+1`. So the **low** (LSB) gate uses `GATE_NEG` and its `carry_o` (`blo_carry`) is routed into the **high** (MSB) gate's `carry_i`; the H gate then runs `GATE_NEG_CARRY`. To negate an int8 B element the mode drives `ctr_l_i[p] = 2` and `ctr_h_i[p] = 3`; to negate independent int4 elements it drives both halves to `2` and the routed carry is simply ignored by the H gate's `GATE_NEG` case.

### H/L convention & even/odd DP8 mapping

Finally the two gated halves are written to the pair's two DP8 outputs — high nibbles to the **even** DP8, low nibbles to the **odd** DP8:

```systemverilog
for (e = 0; e < NUM_B_ELEM; e++) begin : gen_pack
    assign b_dp8_o[2*p+0][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = bhi_gated[e]; // even DP8 = HIGH nibbles
    assign b_dp8_o[2*p+1][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = blo_gated[e]; // odd  DP8 = LOW  nibbles
end
```

So the convention is fixed: **even DP8 `2p` carries the HIGH nibble** (gated by `ctr_h`), **odd DP8 `2p+1` carries the LOW nibble** (gated by `ctr_l`) — matching the `modes.xlsx` dispatch. The per-mode `sel_b`/`ctr_l`/`ctr_h` vectors are exactly the `modes.xlsx` dispatch map and double as the reference for `ctrl`.

Source: [disp_array_b.sv](../../rtl/disp_array_b.sv) — Testbench: [tb_disp_array.sv](../../tb/tb_disp_array.sv)
