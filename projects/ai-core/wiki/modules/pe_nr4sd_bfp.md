# Processing Element (NR4SD BFP)

`pe_nr4sd_bfp` — the [pe_bfp](./pe_bfp.md) core built on [pe_array_nr4sd_bfp](./pe_array_nr4sd_bfp.md) and the **unchanged** [acc_array_bfp](./acc_array_bfp.md). Same shape as `pe_bfp`: operand isolation, then the array, then the accumulator, plus the acc and acc-exp pipeline registers, and the same 3-stage timing.

**4659.40 µm², −12.8 % vs [pe_bfp](./pe_bfp.md)** — 1.6 % above [pe_bpl_b_bfp](./pe_bpl_b_bfp.md)'s 4585.21, with a byte-identical tree and accumulator.

## Purpose

This is the unit the grid multiplies by `N²`, so it is where the two-partial-product recoding has to pay. Against baseline-BFP the split is:

| section   | Δ vs `pe_bfp` | why                                                                                     |
| --------- | ------------- | --------------------------------------------------------------------------------------- |
| DP8 array | **−23.9 %**   | two partial products per lane instead of three Booth rows — 16 cells, 204 FAs, not 332  |
| CPR tree  | **0.0 %**     | byte-identical — `DP8_WIDTH` stays 20, no guard bit, same 1698.32 µm²                   |
| ACC array | 0.0 %         | `acc_array_bfp` reused unchanged (860.77 vs 861.04 µm²)                                 |
| PE glue   | +3.4 %        | two masked B digit buses (40 bits per DP8) in place of one raw bus (32)                 |
| **total** | **−12.8 %**   |                                                                                         |

Where the bit-plane-B PE pays +9.5 % of tree and +2.8 % of accumulator to fund a −39.5 % core, this one takes a −23.9 % core and pays nothing downstream: the saving sits in the leaves and the rest of the tile is `pe_bfp`. The hierarchical totals are 5258.09 vs 5984.76 µm² (baseline-BFP: 3091.57 / 1698.32 / 861.04 / 333.82).

Timing is unchanged: `pe_nr4sd_bfp` closes at **493 MHz** (2000.2 ps path + 28.2 ps setup) against `pe_bfp`'s 494 MHz (1998.2 + 27.6) and `pe_bpl_b_bfp`'s 484 MHz. The critical path is the accumulator carry chain, not the DP8, so the leaf swap is invisible to it.

Power follows the area only in part: **0.889 mW, −3.2 %** vs `pe_bfp`'s 0.919 (`pe_bpl_b_bfp`: 0.771). The whole-int4 modes 1 and 5 are net losses (+5.6 % / +4.3 % at 8×8), because there the baseline's third Booth row is already a constant zero and the hybrid removes nothing while its digit buses still toggle; every sliced-B mode wins, up to −6.4 % in mode 12. See [Per-Mode Synthesis Power](../experiments/syn_mode_pwr.md).

## Parameters

None — fixed to the PE configuration. Key localparams: `NUM_DP8` 16, `A_DP8_WIDTH` 64, `CODE_WIDTH` 2, `BSEL_WIDTH` 3, `B_NR4SD_DP8_WIDTH` 16, `B_BOOTH_DP8_WIDTH` 24, `PE_WIDTH` 20, `EXP_WIDTH` 7, `NUM_LEVEL` 3.

## Interface

Identical to [pe_bfp](./pe_bfp.md) except for the B operand buses:

| Signal                                     | Dir | Width  | Description                                       |
| ------------------------------------------ | --- | ------ | ------------------------------------------------- |
| `clk_i` / `rst_ni`                         | in  | 1      | Clock, asynchronous active-low reset.             |
| `a_dp8_i[0:15]`                            | in  | 64     | 8 × 8-bit raw A lanes (unchanged).                |
| `b_nr4sd_dp8_i[0:15]`                      | in  | 16     | **NEW** — 8 × 2-bit NR4SD⁺ codes, weight 1.       |
| `b_booth_dp8_i[0:15]`                      | in  | 24     | **NEW** — 8 × 3-bit Booth windows, weight 4.      |
| `exp_a_dp8_i` / `exp_b_dp8_i`              | in  | 6      | Per-DP8 format exponents.                         |
| `en_i`                                     | in  | 1      | Operand isolation — masks **five** buses.         |
| `en_level_i` / `sel_shift_i`               | in  | 3      | Per-level register enable; level shift select.    |
| `is_signed_a_i[0:15]`                      | in  | 1      | Per-DP8 A signedness, from `ctrl`.                |
| `acc_i` / `acc_exp_i`                      | in  | 20 / 7 | Per-lane accumulator seed mantissa and scale.     |
| `sel_out_i` / `sel_acc_i` / `prop_carry_i` | in  | 2/1/1  | Tap select, seed vs feedback, carry propagate.    |
| `out_o` / `out_exp_o`                      | out | 20 / 7 | Raw un-normalized result mantissa and scale.      |

**No `is_signed_b_i`** — consumed in [disp_array_b_nr4sd_bfp](./disp_array_b_nr4sd_bfp.md). This is the exact mirror of the bit-plane-B build, where `is_signed_a_i` is the one that disappears.

## Instantiation

```systemverilog
pe_nr4sd_bfp pe_nr4sd_bfp_i (
    .clk_i        (clk_pe),
    .rst_ni       (rst_ni),
    .a_dp8_i      (a_dp8_row[r]),
    .b_nr4sd_dp8_i(b_nr4sd_dp8_col[c]),
    .b_booth_dp8_i(b_booth_dp8_col[c]),
    .exp_a_dp8_i  (exp_a_dp8_row[r]),
    .exp_b_dp8_i  (exp_b_dp8_col[c]),
    .en_i         (en_pe),
    .is_signed_a_i(is_signed_a),
    .sel_shift_i  (sel_shift),
    .en_level_i   (en_level),
    .acc_i        (acc_i[r][c]),
    .acc_exp_i    (acc_exp_i[r][c]),
    .sel_out_i    (sel_out),
    .sel_acc_i    (selacc_q2[0]),
    .prop_carry_i (prop_carry),
    .out_o        (out_q_o[r][c]),
    .out_exp_o    (out_exp_o[r][c])
);
```

## Internal logic

### Five masked buses

`en_i` AND-masks `a_dp8`, both B digit buses and the two exponent buses — one more than [pe_bfp](./pe_bfp.md), because B now arrives as two codes. Masking a code rather than a value still yields an exact zero: an all-zero NR4SD⁺ code is digit 0 and an all-zero Booth window is digit 0, so a masked lane multiplies by zero on both cells and the leaf returns a canonical zero pair.

```systemverilog
for (d = 0; d < NUM_DP8; d++) begin : gen_mask
    assign a_dp8_m[d]       = a_dp8_i[d]       & {A_DP8_WIDTH{en_i}};
    assign b_nr4sd_dp8_m[d] = b_nr4sd_dp8_i[d] & {B_NR4SD_DP8_WIDTH{en_i}};
    assign b_booth_dp8_m[d] = b_booth_dp8_i[d] & {B_BOOTH_DP8_WIDTH{en_i}};
    assign exp_a_dp8_m[d]   = exp_a_dp8_i[d]   & {EXP_IN_WIDTH{en_i}};
    assign exp_b_dp8_m[d]   = exp_b_dp8_i[d]   & {EXP_IN_WIDTH{en_i}};
end
```

As in `pe_bfp`, the PE clock is gated externally by the same enable; the mask keeps the array logic before the first PE register quiet while the shared dispatch keeps toggling. Zeroed exponents are the minimum scale, so a masked DP8 never wins an alignment max. `acc_i` / `acc_exp_i` are per-PE and are not masked. [pe_bpl_b_bfp](./pe_bpl_b_bfp.md) also masks five, with `a_sum_dp8` as its fifth.

### The accumulator is `acc_array_bfp`

Because [pe_array_nr4sd_bfp](./pe_array_nr4sd_bfp.md) exports taps at 18/29/37/38 — baseline-BFP's widths — the accumulator is the unmodified [acc_array_bfp](./acc_array_bfp.md), wired exactly as in `pe_bfp`:

```systemverilog
acc_array_bfp acc_array_bfp_i (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .l0_sum_i    (l0_sum),
    .l0_carry_i  (l0_carry),
    /* … l1/l2/l3 pairs, l0..l3_exp_i … */
    .acc_i       (acc_q2),
    .acc_exp_i   (acc_exp_q2),
    .sel_out_i   (sel_out_i),
    .sel_acc_i   (sel_acc_i),
    .prop_carry_i(prop_carry_i),
    .pe_out_o    (out_o),
    .pe_exp_o    (out_exp_o)
);
```

The bit-plane builds could not do this — their 22-bit leaf row widened the taps to 18/36/40/40 and forced [acc_array_bpl_bfp](./acc_array_bpl_bfp.md).

### Pipeline

Unchanged: `acc_i` and `acc_exp_i` each pass two [reg_n](./reg_n.md) stages so the seed arrives aligned with the L3 tap. Same 3-stage timing as every other PE variant (disp input register upstream, array L0 register, accumulator output register), which is what lets every grid share one `ctrl` pipeline depth.

## Verification

Exercised as part of the full datapath by [tb_acc_array_nr4sd_bfp](../testbenches/tb_acc_array_nr4sd_bfp.md) (11/11, bit-identical to the baseline at `pe_out` with equal exponents) and end-to-end in the grid by [tb_top_NxN_nr4sd_bfp](../testbenches/tb_top_NxN_nr4sd_bfp.md) (66/66).

Source: [pe_nr4sd_bfp.sv](../../rtl/pe_nr4sd_bfp.sv) — Diagram: [pe_nr4sd_bfp](../../doc/diagrams/pe_nr4sd_bfp.excalidraw) — Derivation: [nr4sd_2pp.tex](../../doc/formulas/encodings/nr4sd_2pp.tex)
