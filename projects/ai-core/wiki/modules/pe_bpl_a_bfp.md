# Processing Element (Bit-Plane-A BFP)

`pe_bpl_a_bfp` — the bit-plane variant of the per-PE core [pe_bfp](./pe_bfp.md). Same shape and same 3-stage timing: operand isolation → [pe_array_bpl_a_bfp](./pe_array_bpl_a_bfp.md) → [acc_array_bpl_bfp](./acc_array_bpl_bfp.md), plus the twin acc / acc-exp pipeline registers.

## Purpose

Two things differ from [pe_bfp](./pe_bfp.md), both consequences of where the bit-plane variant puts its B work:

1. **A third operand bus.** The dispatched B arrives as 8 × 5-bit exact signed values **plus** 4 × 6-bit pairwise sums, so `en_i` AND-masks **five** buses instead of four.
2. **No `is_signed_b_i`.** B's signedness is resolved once per column in [disp_array_b_bpl_a_bfp](./disp_array_b_bpl_a_bfp.md), so the flag never reaches the PE.

Everything else — the register structure, the accumulator seed format, the pipeline depth, the port list — is `pe_bfp`'s.

## Parameters

None — fixed to the PE configuration.

| Localparam                    | Value                 | Meaning                                         |
| ----------------------------- | --------------------- | ----------------------------------------------- |
| `NUM_DP8` / `LANES`           | 16 / 8                | DP8 cores and MAC lanes per core (128 MACs).    |
| `A_DP8_WIDTH`                 | 64                    | A operand per DP8 (8 × int8).                   |
| `B_DP8_WIDTH`                 | **40**                | B operand per DP8 (8 × 5-bit), was 32.          |
| `B_SUM_WIDTH`                 | **24**                | **NEW** — pair-sum bus per DP8 (4 × 6-bit).     |
| `PE_WIDTH` / `EXP_WIDTH`      | 20 / 7                | Accumulator lane word and product-domain scale. |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | **18 / 36 / 40 / 40** | Tap widths between array and accumulator.       |

## Interface

| Signal                                     | Dir | Width     | Description                                  |
| ------------------------------------------ | --- | --------- | -------------------------------------------- |
| `clk_i` / `rst_ni`                         | in  | 1         | Clock, asynchronous active-low reset.        |
| `a_dp8_i[0:15]`                            | in  | 64 each   | A operand per DP8.                           |
| `b_dp8_i[0:15]`                            | in  | 40 each   | **CHANGED** — B as exact signed values.      |
| `b_sum_dp8_i[0:15]`                        | in  | 24 each   | **NEW** — pairwise B sums.                   |
| `exp_a_dp8_i` / `exp_b_dp8_i[0:15]`        | in  | 6 each    | Per-DP8 format exponents.                    |
| `en_i`                                     | in  | 1         | PE enable — masks all five operand buses.    |
| `en_level_i[2:0]`                          | in  | 1 each    | Per-level tree isolation.                    |
| `is_signed_a_i[0:15]`                      | in  | 1 each    | Per-DP8 A signedness.                        |
| `sel_shift_i[2:0]`                         | in  | 1 each    | Per-level shift enable.                      |
| `acc_i[0:7]` / `acc_exp_i[0:7]`            | in  | 20 / 7    | Accumulator seed mantissa and scale.         |
| `sel_out_i` / `sel_acc_i` / `prop_carry_i` | in  | 2 / 1 / 1 | Tap level, seed-vs-feedback, fusion carry.   |
| `out_o[0:7]` / `out_exp_o[0:7]`            | out | 20 / 7    | Raw un-normalized result mantissa and scale. |

**No `is_signed_b_i`** — this is the one port `pe_bfp` has that `pe_bpl_a_bfp` does not.

## Instantiation

```systemverilog
pe_bpl_a_bfp pe_bpl_a_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .b_dp8_i(b_dp8), .b_sum_dp8_i(b_sum_dp8),
    .exp_a_dp8_i(exp_a_dp8), .exp_b_dp8_i(exp_b_dp8),
    .en_i(en_pe), .en_level_i(en_level),
    .is_signed_a_i(is_signed_a), .sel_shift_i(sel_shift),
    .acc_i(acc), .acc_exp_i(acc_exp),
    .sel_out_i(sel_out), .sel_acc_i(sel_acc), .prop_carry_i(prop_carry),
    .out_o(out_q), .out_exp_o(out_exp)
);
```

## Internal logic

### Five-bus operand isolation

`en_i` gates every operand bus so a disabled PE presents a constant zero to its whole datapath — combinational AND masks, not registers:

```systemverilog
assign a_dp8_m[d]     = a_dp8_i[d]     & {A_DP8_WIDTH{en_i}};
assign b_dp8_m[d]     = b_dp8_i[d]     & {B_DP8_WIDTH{en_i}};
assign b_sum_dp8_m[d] = b_sum_dp8_i[d] & {B_SUM_WIDTH{en_i}};
assign exp_a_dp8_m[d] = exp_a_dp8_i[d] & {EXP_IN_WIDTH{en_i}};
assign exp_b_dp8_m[d] = exp_b_dp8_i[d] & {EXP_IN_WIDTH{en_i}};
```

Masking `b_sum_dp8` matters as much as masking `b_dp8`: it is the fourth input of every bit-plane multiplexer, so leaving it live would keep a gated PE toggling at the selection stage even with `b_dp8` held at zero.

### Register structure

Unchanged from [pe_bfp](./pe_bfp.md) — four [reg_n](./reg_n.md) banks forming the twin two-deep acc / acc-exp pipelines (`reg_acc1`/`reg_acc2`, `reg_accexp1`/`reg_accexp2`), aligning the seed with the array's L0 stage. The exponent seed and feedback share the mantissa format: a 20-bit lane word, 40 bits split H/L over a lane pair, plus the 7-bit product-domain scale. The raw accumulator mantissa and scale leave un-normalized on `out_o` / `out_exp_o`.

## Area

`5148.90` vs `5345.99` µm² for [pe_bfp](./pe_bfp.md) — **−3.7 %**, flat synthesis. That per-PE saving is the `N²` term the grid multiplies; see [Synthesis Area](../experiments/syn_area.md) and [Intra-PE Area](../experiments/syn_pe_area.md) for the DP8-array / tree / accumulator split.

## Verification

Exercised end to end by [tb_top_NxN_bpl_a_bfp](../testbenches/tb_top_NxN_bpl_a_bfp.md) at the grid level; its two halves are proven separately by [tb_pe_array_bpl_a_bfp](../testbenches/tb_pe_array_bpl_a_bfp.md) and [tb_acc_array_bpl_a_bfp](../testbenches/tb_acc_array_bpl_a_bfp.md).

Source: [pe_bpl_a_bfp.sv](../../rtl/pe_bpl_a_bfp.sv) — Diagram: [pe_bpl_a_bfp](../../doc/diagrams/pe_bpl_a_bfp.excalidraw)
