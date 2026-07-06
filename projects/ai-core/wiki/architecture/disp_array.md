---
type: architecture
title: Dispatch Array
description: Operand router — dispatches the two 256-bit PE operands to the 16 DP8s via per-pair 4->1 block selects, a B high/low split, and per-DP8 B gating.
resource: rtl/disp_array.sv
---

# Dispatch Array

`disp_array` — operand-dispatch array: it registers the two 256-bit PE operands (`pe_in_a_i`, `pe_in_b_i`) and routes them to the 16 [dp_8](../modules/dp_8.md) cores using one 4→1 block select per operand per pair, a fixed B high/low split, and per-DP8 B gating. It is instantiated inside [pe_array](./pe_array.md).

## Purpose

Turns the two 256-bit operands — each four 64-bit blocks — into the 16 per-DP8 operand pairs the array needs, without a full crossbar. The 16 DP8s form 8 pairs, and each pair reads exactly one A block and one B block (the dispatch rule from `modes.xlsx`). It is **data-path only**: operand signedness (`is_signed_a`/`is_signed_b` per DP8) is a mode-decode control that `pe_ctrl` sends straight to the DP8s, not routed here.

## Parameters

**None — fixed to the PE configuration.** `disp_array` exposes no external parameters; all sizing is `localparam`, hard-wired to the one PE geometry. The key locals:

| Localparam     | Value | Meaning                                                        |
| -------------- | ----- | -------------------------------------------------------------- |
| `NUM_BLK`      | 4     | 64-bit blocks per 256-bit operand.                             |
| `BLK_WIDTH`    | 64    | Bit width of one operand block.                                |
| `NUM_PAIR`     | 8     | DP8 pairs (each pair = two adjacent DP8s).                     |
| `NUM_DP8`      | 16    | Total DP8 cores (`2 × NUM_PAIR`).                              |
| `SEL_WIDTH`    | 2     | Block-select width, `$clog2(NUM_BLK)`.                         |
| `A_DP8_WIDTH`  | 64    | A operand per DP8 (`= BLK_WIDTH`, 8 × int8).                   |
| `B_DP8_WIDTH`  | 32    | B operand per DP8 (`= BLK_WIDTH/2`, 8 × int4).                 |
| `B_ELEM_WIDTH` | 4     | One B element (int4 nibble).                                   |
| `NUM_B_ELEM`   | 8     | int4 elements in a 32-bit B half (`B_DP8_WIDTH/B_ELEM_WIDTH`). |
| `OP_WIDTH`     | 2     | Width of a per-lane B-gate op code.                            |

## Interface

| Signal          | Dir | Width   | Description                                                                          |
| --------------- | --- | ------- | ------------------------------------------------------------------------------------ |
| `clk_i`         | in  | 1       | Clock.                                                                               |
| `rst_ni`        | in  | 1       | Asynchronous active-low reset.                                                       |
| `pe_in_a_i`     | in  | 256     | Operand A — four 64-bit blocks (block `b` = `[b*64 +: 64]`).                         |
| `pe_in_b_i`     | in  | 256     | Operand B — four 64-bit blocks.                                                      |
| `sel_a_i[0:7]`  | in  | 2 each  | Per-pair A-block select (4→1).                                                       |
| `sel_b_i[0:7]`  | in  | 2 each  | Per-pair B-block select (4→1).                                                       |
| `ctr_l_i[0:7]`  | in  | 2 each  | Odd-DP8 (`2p+1`, low L) B-gate op: `0` pass, `1` zero, `2` negate, `3` negate-carry. |
| `ctr_h_i[0:7]`  | in  | 2 each  | Even-DP8 (`2p`, high H) B-gate op: `0` pass, `1` zero, `2` negate, `3` negate-carry. |
| `a_dp8_o[0:15]` | out | 64 each | A operand per DP8 (8 × int8).                                                        |
| `b_dp8_o[0:15]` | out | 32 each | B operand per DP8 (8 × int4).                                                        |

## Instantiation

```systemverilog
disp_array disp_array_i (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .pe_in_a_i(pe_in_a),   // 256-bit A operand (4 x 64-bit blocks)
    .pe_in_b_i(pe_in_b),   // 256-bit B operand (4 x 64-bit blocks)
    .sel_a_i  (sel_a),     // [0:7] per-pair A-block select
    .sel_b_i  (sel_b),     // [0:7] per-pair B-block select
    .ctr_l_i  (ctr_l),     // [0:7] odd-DP8  (low  half) B-gate op
    .ctr_h_i  (ctr_h),     // [0:7] even-DP8 (high half) B-gate op
    .a_dp8_o  (a_dp8),     // [0:15] A per DP8 (64b)
    .b_dp8_o  (b_dp8)      // [0:15] B per DP8 (32b)
);
```

## Internal logic

The whole module is two input register banks followed by a `NUM_PAIR`-wide generate loop; there is no state past the input registers, so the dispatch itself is purely combinational. Read top-to-bottom it is: reshape → register → per-pair A mux → per-pair B mux → split → gate → pack.

### Input registering & block reshape

The two operands arrive as flat 256-bit buses. A first generate loop slices each into `NUM_BLK` = 4 unpacked 64-bit blocks (block `b` occupies bits `[b*64 +: 64]`):

```systemverilog
for (b = 0; b < NUM_BLK; b++) begin : gen_reshape
    assign a_blk[b] = pe_in_a_i[b*BLK_WIDTH +: BLK_WIDTH];
    assign b_blk[b] = pe_in_b_i[b*BLK_WIDTH +: BLK_WIDTH];
end
```

Both block arrays are then latched by a [reg_n](../modules/reg_n.md) bank each — `SIZE = NUM_BLK` registers of `WIDTH = BLK_WIDTH` bits, sharing `clk_i`/`rst_ni`:

```systemverilog
reg_n #(.WIDTH(BLK_WIDTH), .SIZE(NUM_BLK)) reg_n_a_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(a_blk), .q_o(a_blk_q)
);
reg_n #(.WIDTH(BLK_WIDTH), .SIZE(NUM_BLK)) reg_n_b_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(b_blk), .q_o(b_blk_q)
);
```

`a_blk_q`/`b_blk_q` are the registered blocks; everything downstream reads them, so the operands are captured once and the dispatch is a combinational fan-out of that single registered copy. `reg_n` has no enable — the operands are expected to be held stable by the PE for the cycle they are consumed.

### Per-pair A mux (shared)

Inside the `gen_pair` loop, one entry per pair `p` (0..7), a 4→1 [mux_n](../modules/mux_n.md) over the four registered A blocks picks the single A block this pair uses, indexed by `sel_a_i[p]`:

```systemverilog
mux_n #(.WIDTH(BLK_WIDTH), .SIZE(NUM_BLK)) mux_n_a_i (
    .in_i(a_blk_q), .sel_i(sel_a_i[p]), .out_o(a_sel)
);

assign a_dp8_o[2*p+0] = a_sel;
assign a_dp8_o[2*p+1] = a_sel;
```

The selected A block feeds **both** DP8s of the pair unchanged — `a_dp8_o[2p]` and `a_dp8_o[2p+1]` are the same 64-bit value (8 × int8). A is never gated here (see the H/L section for why zeroing B is enough to idle a lane), so A passes straight from the mux to the two outputs.

### Per-pair B mux + high/low split

A second 4→1 `mux_n` over the four registered B blocks picks this pair's B block under `sel_b_i[p]`:

```systemverilog
mux_n #(.WIDTH(BLK_WIDTH), .SIZE(NUM_BLK)) mux_n_b_i (
    .in_i(b_blk_q), .sel_i(sel_b_i[p]), .out_o(b_sel)
);
```

The 64-bit B block is two 32-bit halves, each holding `NUM_B_ELEM` = 8 int4 nibbles. The **low** half (`b_sel[31:0]`) is destined for the odd DP8, the **high** half (`b_sel[63:32]`) for the even DP8. A small loop splits both halves into per-element nibbles and (for now) ties the low gate's carry-in to zero:

```systemverilog
for (e = 0; e < NUM_B_ELEM; e++) begin : gen_split
    assign blo_nib[e] = b_sel[e*B_ELEM_WIDTH +: B_ELEM_WIDTH];               // low  half nibble e
    assign bhi_nib[e] = b_sel[B_DP8_WIDTH + e*B_ELEM_WIDTH +: B_ELEM_WIDTH]; // high half nibble e
    assign blo_cin[e] = 1'b0;
end
```

So for element index `e`, `blo_nib[e]` is the low nibble and `bhi_nib[e]` the high nibble — i.e. an int8 B element `e` is `{bhi_nib[e], blo_nib[e]}`, its two halves living in the two different DP8s of the pair.

### B gating (pass / zero / negate)

Each 32-bit B half then passes through its own [gate_b_n](../modules/gate_b_n.md) — 8 nibbles, all sharing one op code. The **low** half is gated by `ctr_l_i[p]`, the **high** half by `ctr_h_i[p]`:

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

Per int4 element, a gate can **pass** (`0`, most modes), **zero** (`1`, idle DP8 — e.g. mode 6), or **negate** (`2`, two's-complement, the imaginary-B term in the complex modes). Because a lane is idled by zeroing its B (`a·0 = 0`), no A gate is needed — this is the reason `disp_array` is B-gate-only. Negation is only ever applied to B.

### Carry-chained negate for int8

A single int4 negate (`gate_b_n` op `2`, `GATE_NEG`) is exact on its own 4 bits. But an **int8** B element is split across the two gates — its low nibble is in the L gate, its high nibble in the H gate — and two's-complement negation is `~x + 1`, whose `+1` must ripple as one carry from the least-significant nibble upward. Negating each nibble independently would drop that carry and give the wrong int8.

`gate_b_n` therefore exposes a per-element `carry_o` on `GATE_NEG` and provides a fourth op `GATE_NEG_CARRY` (`3`) that adds the incoming `carry_i` in place of the fixed `+1`:

```systemverilog
GATE_NEG:       {carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + 1'b1;      // low nibble: ~x + 1, emit carry
GATE_NEG_CARRY: {carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + carry_i[i]; // high nibble: ~x + carry_in
```

`disp_array` wires the chain so the exact int8 negate is available: the **low** (LSB) gate uses `GATE_NEG` and its `carry_o` (`blo_carry`) is routed into the **high** (MSB) gate's `carry_i`; the H gate then runs `GATE_NEG_CARRY`, and its own `carry_o` is left open at the top of the chain. `blo_cin` (the L gate's carry-in) is tied to `0` because it is the bottom of the chain. To negate an int8 B element the mode drives `ctr_l_i[p] = 2` (`GATE_NEG`) and `ctr_h_i[p] = 3` (`GATE_NEG_CARRY`); to negate independent int4 elements it drives both halves to `2`, and the routed carry is simply ignored by the H gate's `GATE_NEG` case. The wiring is always present; whether the carry is consumed is decided purely by the H-gate op code.

### H/L convention & even/odd DP8 mapping

Finally the two gated halves are written to the pair's two DP8 outputs — high nibbles to the **even** DP8, low nibbles to the **odd** DP8:

```systemverilog
for (e = 0; e < NUM_B_ELEM; e++) begin : gen_pack
    assign b_dp8_o[2*p+0][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = bhi_gated[e]; // even DP8 = HIGH nibbles
    assign b_dp8_o[2*p+1][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = blo_gated[e]; // odd  DP8 = LOW  nibbles
end
```

So the convention is fixed: **even DP8 `2p` carries the HIGH nibble** (gated by `ctr_h`), **odd DP8 `2p+1` carries the LOW nibble** (gated by `ctr_l`) — matching the `modes.xlsx` dispatch. Combined with the carry chain above, the two DP8s of a pair jointly hold the high and low halves of the same int8 B, with the negate carry flowing from the odd lane (low) into the even lane (high). The per-mode `sel_a`/`sel_b`/`ctr_l`/`ctr_h` vectors are exactly the `modes.xlsx` dispatch map and double as the reference for `pe_ctrl`; the testbench drives them straight from that table and checks every DP8 output against a golden block-select / high-low-split / per-int4-gate model.

Source: [disp_array.sv](../../rtl/disp_array.sv) — Testbench: [tb_disp_array.sv](../../tb/tb_disp_array.sv) — Diagram: [disp_array](../../doc/diagrams/disp_array.md)
