# Exponent Dispatch A (BFP)

`disp_array_exp_a_bfp` — the BFP exponent-sideband counterpart of [disp_array_a](./disp_array_a.md): one instance per grid row, next to the A mantissa dispatcher it mirrors, routing the four per-block A **format exponents** to the 16 DP8s with the same 4→1 block select, then zeroing the exponent of any idle DP8 so it can never win an alignment max in [pe_array_bfp](./pe_array_bfp.md).

## Purpose

BFP is a 6-bit exponent sideband bolted onto the integer operands: the 256-bit A word carries **one exponent per 64-bit block** (the source rule), so a row's A exponents are just four 6-bit values. This module dispatches them exactly the way [disp_array_a](./disp_array_a.md) dispatches the mantissa blocks — a per-pair 4→1 select on the shared `sel_a`, the chosen block duplicated onto both DP8s of the pair — so each exponent rides to the same DP8 as its mantissa.

Two things make it more than a straight copy of the mantissa dispatcher:

- **Both halves gate to zero on idle.** The mantissa A path needs no gate — a zeroed B mantissa already kills the product (`a·0 = 0`). But exponents **add** in the PE array (`scale = e_A + e_B`), so a DP8 idled only by its B gate would still present its leftover `e_A`; at a tree merge that stray scale could win the exponent max and arithmetic-right-shift the *active* data. So each half is forced to the minimum scale (all-zeros) whenever its lane carries the ZERO gate code — the even DP8 by `ctr_h_i`, the odd by `ctr_l_i`, mirroring the B dispatcher's per-half idle decode.
- **ZERO-decode only — never a negate.** Only the ZERO code masks; the NEG / NEG_CARRY codes pass the exponent through unchanged, because negating a mantissa (the complex-mode `−b_im`) gives `−m·2^e` — the scale is untouched. Reusing [disp_array_b](./disp_array_b.md)'s `gate_b_n` here would wrongly negate the exponents in the complex modes 10/11.

The 24-bit exponent word is registered on input, in step with `disp_array_a`'s 256-bit operand register; the dispatch below the register is combinational and broadcast to the row's PEs.

## Parameters

None — fixed to the PE configuration; all sizing is `localparam`. The key ones:

| Localparam  | Value | Meaning                                              |
| ----------- | ----- | ---------------------------------------------------- |
| `NUM_BLK`   | 4     | 64-bit A blocks per 256-bit operand (one exp each).  |
| `EXP_WIDTH` | 6     | Stored A format-exponent width.                      |
| `NUM_PAIR`  | 8     | DP8 pairs (each pair = two adjacent DP8s).           |
| `NUM_DP8`   | 16    | Total DP8 cores (`2 × NUM_PAIR`).                    |
| `SEL_WIDTH` | 2     | Block-select width, `$clog2(NUM_BLK)`.               |
| `OP_WIDTH`  | 2     | B-gate op-code width — only the ZERO code is read.   |

The idle mask fires on a single code: `localparam logic [OP_WIDTH-1:0] GATE_ZERO = 2'b01;`.

## Interface

| Signal              | Dir | Width  | Description                                                                       |
| ------------------- | --- | ------ | --------------------------------------------------------------------------------- |
| `clk_i`             | in  | 1      | Clock (gated per row by the row's ICG).                                           |
| `rst_ni`            | in  | 1      | Asynchronous active-low reset.                                                    |
| `pe_exp_a_i`        | in  | 24     | Row's A exponents — four 6-bit blocks (block `b` = `[b*6 +: 6]`).                 |
| `sel_a_i[0:7]`      | in  | 2 each | Per-pair A-block select (4→1), from `ctrl` — the same vector `disp_array_a` uses. |
| `ctr_l_i[0:7]`      | in  | 2 each | Odd-DP8 (`2p+1`) gate op; ZERO (`2'b01`) masks that half's exponent.              |
| `ctr_h_i[0:7]`      | in  | 2 each | Even-DP8 (`2p`) gate op; ZERO masks that half's exponent.                         |
| `exp_a_dp8_o[0:15]` | out | 6 each | A format exponent per DP8, broadcast to the row's PEs.                            |

## Instantiation

```systemverilog
disp_array_exp_a_bfp disp_array_exp_a_bfp_i (
    .clk_i      (clk_a),          // row-gated clock, shared with disp_array_a
    .rst_ni     (rst_ni),
    .pe_exp_a_i (in_exp_a_i[r]),  // 4 × 6-bit A exponents for row r
    .sel_a_i    (sel_a),          // same per-pair select as the mantissa path
    .ctr_l_i    (ctr_l),
    .ctr_h_i    (ctr_h),
    .exp_a_dp8_o(exp_a_dp8_row[r])
);
```

## Internal logic

Read top-to-bottom: reshape → register → per-pair mux → duplicate → per-half ZERO-gate. There is no state past the input register, so the dispatch is a combinational fan-out.

### Reshape & register

The flat 24-bit word is sliced into four 6-bit blocks and latched by a [reg_n](./reg_n.md) bank in step with the operand register:

```systemverilog
assign exp_blk[b] = pe_exp_a_i[b*EXP_WIDTH +: EXP_WIDTH];
reg_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_BLK)) reg_n_exp_a_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(exp_blk), .q_o(exp_blk_q)
);
```

### Per-pair select and duplicate

One [mux_n](./mux_n.md) per pair picks this pair's A exponent under `sel_a_i[p]` — the same select the mantissa dispatcher uses — and the chosen value is duplicated onto both halves of the pair (an A block feeds both DP8s of the pair unchanged):

```systemverilog
mux_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_BLK)) mux_n_exp_i (
    .in_i(exp_blk_q), .sel_i(sel_a_i[p]), .out_o(exp_sel)
);
assign exp_pair[0] = exp_sel;
assign exp_pair[1] = exp_sel;
```

### Per-half idle gate

Each duplicated exponent then passes a [gate_n](./gate_n.md) that forces it to the minimum scale when its half is idle — the even DP8 on `ctr_h_i[p] == GATE_ZERO`, the odd on `ctr_l_i[p]`:

```systemverilog
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_h_i (
    .in_i(exp_pair[0:0]), .sel_i(ctr_h_i[p] == GATE_ZERO), .out_o(exp_h)
);
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_l_i (
    .in_i(exp_pair[1:1]), .sel_i(ctr_l_i[p] == GATE_ZERO), .out_o(exp_l)
);
assign exp_a_dp8_o[2*p+0] = exp_h[0];   // even DP8
assign exp_a_dp8_o[2*p+1] = exp_l[0];   // odd  DP8
```

A gate fires **per half, not per pair** — mode 5 idles only the low half on pairs 0–3 and only the high half on pairs 4–7, so the two outputs of a pair gate independently. Because the idle value is all-zeros, this relies on the BFP exponent being **unsigned** (a signed encoding would need the most-negative code as the idle floor).

## Notes

- **No scale sum here.** The A exponents leave as bare 6-bit values; the per-DP8 scale `e_A + e_B` is formed only where the A (row) and B (column) sidebands finally meet — in [pe_array_bfp](./pe_array_bfp.md), one `add_n` per DP8.
- Consumer: [pe_array_bfp](./pe_array_bfp.md) via [pe_bfp](./pe_bfp.md); the mirror B side is [disp_array_exp_b_bfp](./disp_array_exp_b_bfp.md). All three are wired together in [top_NxN_bfp](../architectures/top_NxN_bfp.md), where this instance shares the row clock-gate with its `disp_array_a`.

Source: [disp_array_exp_a_bfp.sv](../../rtl/disp_array_exp_a_bfp.sv) — Diagram: [disp_array_exp_a_bfp](../../doc/diagrams/disp_array_exp_a_bfp.excalidraw)
