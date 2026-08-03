# Exponent Dispatch B (BFP)

`disp_array_exp_b_bfp` — the BFP exponent-sideband counterpart of [disp_array_b](./disp_array_b.md): one instance per grid column, next to the B mantissa dispatcher it mirrors, routing the four per-block B exponent chunks to the 16 DP8s with the same 4→1 block select **and the same fixed high/low split**, then zeroing the exponent of any idle DP8 so it can never win an alignment max in [pe_array_bfp](./pe_array_bfp.md).

## Purpose

Where the A side carries one exponent per 64-bit block (see [disp_array_exp_a_bfp](./disp_array_exp_a_bfp.md)), the B side carries **two exponents per block**. B packing can cut a source block across chunks, so a packed 64-bit B block may hold the two 32-bit halves of two *different* source blocks — two distinct scales — which is exactly why the transport rule gives B eight exponent slots (per 32-bit half) against A's four. Each block therefore arrives as a **12-bit chunk**: bits `[11:6]` are the exponent of the block's **high (H)** half and go to the even DP8 (`2p`), bits `[5:0]` the **low (L)** half and go to the odd DP8 (`2p+1`) — the identical H/L, even/odd mapping [disp_array_b](./disp_array_b.md) uses on the mantissa nibbles, so each exponent lands on the same DP8 as its mantissa half.

Otherwise the idle discipline is the same as the A side:

- **Both halves gate to zero on idle.** Exponents add in the PE array (`scale = e_A + e_B`), so an idle DP8 must present the minimum scale or its leftover `e_B` could win an alignment max and right-shift active data. Each half is masked to all-zeros when its lane carries the ZERO gate code — the H half by `ctr_h_i`, the L half by `ctr_l_i` — per half, not per pair.
- **ZERO-decode only — never a negate.** NEG / NEG_CARRY pass the exponent through unchanged (negating a mantissa leaves its scale). Reusing `gate_b_n` here would negate the exponents in the complex modes 10/11 — hence a plain [gate_n](./gate_n.md) driven off the ZERO comparison, not `disp_array_b`'s gate.

The 48-bit exponent word is registered on input, in step with `disp_array_b`'s 256-bit operand register; the dispatch below the register is combinational and broadcast to the column's PEs.

## Parameters

None — fixed to the PE configuration; all sizing is `localparam`. The key ones:

| Localparam  | Value | Meaning                                                 |
| ----------- | ----- | ------------------------------------------------------- |
| `NUM_BLK`   | 4     | 64-bit B blocks per 256-bit operand.                    |
| `EXP_WIDTH` | 6     | Stored B format-exponent width (one per 32-bit half).   |
| `CHK_WIDTH` | 12    | Per-block chunk = two half-exponents (`2 × EXP_WIDTH`). |
| `NUM_PAIR`  | 8     | DP8 pairs.                                              |
| `NUM_DP8`   | 16    | Total DP8 cores (`2 × NUM_PAIR`).                       |
| `SEL_WIDTH` | 2     | Block-select width, `$clog2(NUM_BLK)`.                  |
| `OP_WIDTH`  | 2     | B-gate op-code width — only the ZERO code is read.      |

The idle mask fires on a single code: `localparam logic [OP_WIDTH-1:0] GATE_ZERO = 2'b01;`.

## Interface

| Signal              | Dir | Width  | Description                                                                                    |
| ------------------- | --- | ------ | ---------------------------------------------------------------------------------------------- |
| `clk_i`             | in  | 1      | Clock (gated per column by the column's ICG).                                                  |
| `rst_ni`            | in  | 1      | Asynchronous active-low reset.                                                                 |
| `pe_exp_b_i`        | in  | 48     | Column's B exponents — four 12-bit chunks (chunk `b` = `[b*12 +: 12]`, `[11:6]`=H, `[5:0]`=L). |
| `sel_b_i[0:7]`      | in  | 2 each | Per-pair B-block select (4→1), from `ctrl` — the same vector `disp_array_b` uses.              |
| `ctr_l_i[0:7]`      | in  | 2 each | Odd-DP8 (`2p+1`, L half) gate op; ZERO (`2'b01`) masks that half's exponent.                   |
| `ctr_h_i[0:7]`      | in  | 2 each | Even-DP8 (`2p`, H half) gate op; ZERO masks that half's exponent.                              |
| `exp_b_dp8_o[0:15]` | out | 6 each | B format exponent per DP8, broadcast to the column's PEs.                                      |

## Instantiation

```systemverilog
disp_array_exp_b_bfp disp_array_exp_b_bfp_i (
    .clk_i      (clk_b),          // column-gated clock, shared with disp_array_b
    .rst_ni     (rst_ni),
    .pe_exp_b_i (in_exp_b_i[c]),  // 4 × 12-bit B exponent chunks for column c
    .sel_b_i    (sel_b),          // same per-pair select as the mantissa path
    .ctr_l_i    (ctr_l),
    .ctr_h_i    (ctr_h),
    .exp_b_dp8_o(exp_b_dp8_col[c])
);
```

## Internal logic

Read top-to-bottom: reshape → register → per-pair mux → H/L split → per-half ZERO-gate. There is no state past the input register, so the dispatch is a combinational fan-out.

### Reshape & register

The flat 48-bit word is sliced into four 12-bit chunks and latched by a [reg_n](./reg_n.md) bank in step with the operand register:

```systemverilog
assign exp_blk[b] = pe_exp_b_i[b*CHK_WIDTH +: CHK_WIDTH];
reg_n #(.WIDTH(CHK_WIDTH), .SIZE(NUM_BLK)) reg_n_exp_b_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(exp_blk), .q_o(exp_blk_q)
);
```

### Per-pair select and H/L split

One [mux_n](./mux_n.md) per pair picks this pair's 12-bit chunk under `sel_b_i[p]`, then the chunk is split — high half-exponent to output 0 (even DP8), low to output 1 (odd DP8), exactly the mantissa dispatcher's `even = H, odd = L` convention:

```systemverilog
mux_n #(.WIDTH(CHK_WIDTH), .SIZE(NUM_BLK)) mux_n_exp_i (
    .in_i(exp_blk_q), .sel_i(sel_b_i[p]), .out_o(exp_sel)
);
assign exp_split[0] = exp_sel[CHK_WIDTH-1:EXP_WIDTH];   // high half → even DP8
assign exp_split[1] = exp_sel[EXP_WIDTH-1:0];           // low  half → odd  DP8
```

### Per-half idle gate

Each split exponent then passes a [gate_n](./gate_n.md) that forces it to the minimum scale when its half is idle — the H half on `ctr_h_i[p] == GATE_ZERO`, the L half on `ctr_l_i[p]`:

```systemverilog
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_h_i (
    .in_i(exp_split[0:0]), .sel_i(ctr_h_i[p] == GATE_ZERO), .out_o(exp_h)
);
gate_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) gate_n_l_i (
    .in_i(exp_split[1:1]), .sel_i(ctr_l_i[p] == GATE_ZERO), .out_o(exp_l)
);
assign exp_b_dp8_o[2*p+0] = exp_h[0];   // even DP8 = H exponent
assign exp_b_dp8_o[2*p+1] = exp_l[0];   // odd  DP8 = L exponent
```

Because the idle value is all-zeros, this relies on the BFP exponent being **unsigned** (a signed encoding would need the most-negative code as the idle floor). For int16 / complex operands several chunk slots carry copies of one source exponent (byte/nibble planes, Re/Im planes), so the H and L exponents of such a block are equal by construction — the split is transparent there.

## Notes

- **No scale sum here.** The B exponents leave as bare 6-bit values; the per-DP8 scale `e_A + e_B` is formed only in [pe_array_bfp](./pe_array_bfp.md), where the row's A sideband and the column's B sideband finally meet, one `add_n` per DP8.
- Consumer: [pe_array_bfp](./pe_array_bfp.md) via [pe_bfp](./pe_bfp.md); the mirror A side is [disp_array_exp_a_bfp](./disp_array_exp_a_bfp.md). All three are wired together in [top_NxN_bfp](../architectures/top_NxN_bfp.md), where this instance shares the column clock-gate with its `disp_array_b`.

Source: [disp_array_exp_b_bfp.sv](../../rtl/disp_array_exp_b_bfp.sv) — Diagram: [disp_array_exp_b_bfp](../../doc/diagrams/disp_array_exp_b_bfp.excalidraw)
