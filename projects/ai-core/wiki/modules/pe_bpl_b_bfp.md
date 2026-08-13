# Processing Element (Bit-Plane-B BFP)

`pe_bpl_b_bfp` — the [pe_bfp](./pe_bfp.md) core built on [pe_array_bpl_b_bfp](./pe_array_bpl_b_bfp.md) and [acc_array_bpl_bfp](./acc_array_bpl_bfp.md). Same shape as `pe_bfp`: operand isolation, then the array, then the accumulator, plus the acc and acc-exp pipeline registers, and the same 3-stage timing.

**4585.21 µm², −14.2 % vs [pe_bfp](./pe_bfp.md)** — the tile saving that carries the whole variant.

## Purpose

This is the unit the grid multiplies by `N²`, so it is where the bit-plane decomposition has to pay. Against baseline-BFP the split is:

| section   | Δ vs `pe_bfp` | why                                                        |
| --------- | ------------- | ---------------------------------------------------------- |
| DP8 array | **−39.5 %**   | 16 muxes + 4 columns instead of Booth partial products     |
| CPR tree  | +9.5 %        | a 22-bit carry-save row instead of 20, guard bits at L0/L1 |
| ACC array | +2.8 %        | wider taps (36/40/40)                                      |
| PE glue   | +20.1 %       | a fifth masked operand bus                                 |
| **total** | **−14.2 %**   |                                                            |

Timing is essentially unchanged: `pe_bpl_b_bfp` closes at **483.6 MHz** against `pe_bfp`'s 493.6 MHz (**−2.0 %**), so the area comes without a frequency cost worth trading back.

## Parameters

None — fixed to the PE configuration. Key localparams: `NUM_DP8` 16, `IN_WIDTH_A` 9, `SUM_WIDTH` 10, `IN_WIDTH_B` 4, `PE_WIDTH` 20, `EXP_WIDTH` 7, `NUM_LEVEL` 3.

## Interface

Identical to [pe_bfp](./pe_bfp.md) except for the operand buses:

| Signal                                     | Dir | Width  | Description                                    |
| ------------------------------------------ | --- | ------ | ---------------------------------------------- |
| `clk_i` / `rst_ni`                         | in  | 1      | Clock, asynchronous active-low reset.          |
| `a_dp8_i[0:15]`                            | in  | 72     | **CHANGED** — 8 × 9-bit exact signed A lanes.  |
| `a_sum_dp8_i[0:15]`                        | in  | 40     | **NEW** — 4 × 10-bit pairwise A sums.          |
| `b_dp8_i[0:15]`                            | in  | 32     | **CHANGED** — 8 × 4-bit raw int4 B lanes.      |
| `exp_a_dp8_i` / `exp_b_dp8_i`              | in  | 6      | Per-DP8 format exponents.                      |
| `en_i`                                     | in  | 1      | Operand isolation — masks **five** buses.      |
| `en_level_i` / `sel_shift_i`               | in  | 3      | Per-level register enable; level shift select. |
| `is_signed_b_i[0:15]`                      | in  | 1      | Per-DP8 B signedness (idle-masked upstream).   |
| `acc_i` / `acc_exp_i`                      | in  | 20 / 7 | Per-lane accumulator seed mantissa and scale.  |
| `sel_out_i` / `sel_acc_i` / `prop_carry_i` | in  | 2/1/1  | Tap select, seed vs feedback, carry propagate. |
| `out_o` / `out_exp_o`                      | out | 20 / 7 | Raw un-normalized result mantissa and scale.   |

**No `is_signed_a_i`** — resolved in [disp_array_a_bpl_b_bfp](./disp_array_a_bpl_b_bfp.md).

## Instantiation

```systemverilog
pe_bpl_b_bfp pe_bpl_b_bfp_i (
    .clk_i(clk_pe), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8_row[r]), .a_sum_dp8_i(a_sum_dp8_row[r]),
    .b_dp8_i(b_dp8_col[c]),
    .exp_a_dp8_i(exp_a_dp8_row[r]), .exp_b_dp8_i(exp_b_dp8_col[c]),
    .en_i(en_pe), .en_level_i(en_level), .is_signed_b_i(is_signed_b_g),
    .sel_shift_i(sel_shift), .acc_i(acc_i[r][c]), .acc_exp_i(acc_exp_i[r][c]),
    .sel_out_i(sel_out), .sel_acc_i(sel_acc_q), .prop_carry_i(prop_carry),
    .out_o(out_q_o[r][c]), .out_exp_o(out_exp_o[r][c])
);
```

## Internal logic

### Five masked buses

`en_i` AND-masks `a_dp8`, `a_sum_dp8`, `b_dp8`, `exp_a_dp8` and `exp_b_dp8` — one more than [pe_bfp](./pe_bfp.md), because the pair sums are a third operand. Masking them matters: they land on the **data** side of the bit-plane multiplexers, so a gated PE would otherwise keep toggling its mux inputs even with its selects quiet.

```systemverilog
assign a_dp8_m[d]     = a_dp8_i[d]     & {A_DP8_WIDTH{en_i}};
assign a_sum_dp8_m[d] = a_sum_dp8_i[d] & {A_SUM_WIDTH{en_i}};
assign b_dp8_m[d]     = b_dp8_i[d]     & {B_DP8_WIDTH{en_i}};
```

[pe_bpl_a_bfp](./pe_bpl_a_bfp.md) masks the same five, with `b_sum_dp8` in place of `a_sum_dp8`.

### Pipeline

Unchanged: `acc_i` and `acc_exp_i` each pass two [reg_n](./reg_n.md) stages before reaching the accumulator, so the seed arrives aligned with the L3 tap. Same 3-stage timing as every other PE variant, which is what lets all six grids share one `ctrl` pipeline depth.

## Verification

Exercised as part of the full datapath by [tb_acc_array_bpl_b_bfp](../testbenches/tb_acc_array_bpl_b_bfp.md) (11/11) and end-to-end in the grid by [tb_top_NxN_bpl_b_bfp](../testbenches/tb_top_NxN_bpl_b_bfp.md) (66/66).

Source: [pe_bpl_b_bfp.sv](../../rtl/pe_bpl_b_bfp.sv) — Diagram: [pe_bpl_b_bfp](../../doc/diagrams/pe_bpl_b_bfp.excalidraw)
