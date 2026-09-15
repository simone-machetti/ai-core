# PE Grid (NR4SD BFP)

`top_NxN_nr4sd_bfp` — the **NR4SD BFP** N × N grid, the [top_NxN_bfp](./top_NxN_bfp.md) analogue built on the recoding **column** dispatch and PE ([disp_array_b_nr4sd_bfp](../modules/disp_array_b_nr4sd_bfp.md), [pe_nr4sd_bfp](../modules/pe_nr4sd_bfp.md)). It tiles N² cores, sharing operand A (mantissa + exponent) along each row and B along each column, so PE[r][c] evaluates `A[r] · B[c]` in block floating point — with the same values as `top_NxN_bfp` in every mode with equal block exponents, and in every mode but 2 and 6 with unequal ones (see [below](#modes-2-and-6-with-unequal-block-exponents)).

**−12.5 % area and −2.9 % power at 8×8 against baseline-BFP, crossover at N = 1 — within 1.3 points of the bit-plane-B grid on area, at a byte-identical tree and accumulator.**

## Purpose

Booth recodes B inside every PE, and B is a function of the column alone. The grid follows one rule:

> **Recode the shared operand where it is shared.**

Hoisting the recoders into the column dispatcher turns an `N²` cost into an `N` one, and choosing the NR4SD⁺/Booth **hybrid** — one NR4SD⁺ digit at weight 1 and one Booth digit at weight 4 per nibble — gets each lane down to **two** partial products instead of three, so the tile loses a third of its partial-product rows as well:

| term                                        | cost                        | scales as |
| ------------------------------------------- | --------------------------- | --------- |
| recoders ([nr4sd_r4](../modules/nr4sd_r4.md)) + cross-nibble links | `N` columns × 16 DP8 × 8 | **O(N)**  |
| partial products + compression              | `N²` PEs                    | **O(N²)** |

The overhead is `+13.0 %` on one dispatcher (`526.91` vs `466.33` µm²) against a per-tile saving of `686.59` µm² of PE, so **the crossover is at N = 1**: smaller than baseline-BFP at every size, including 2×2.

Measured against [top_NxN_bfp](./top_NxN_bfp.md) (bit-plane B in brackets):

| metric | 8×8                   | 16×16                 | asymptote        | crossover |
| ------ | --------------------- | --------------------- | ---------------- | --------- |
| area   | **−12.45 %** (−13.7)  | **−12.64 %** (−13.9)  | −12.8 % (−14.2)  | N = 1     |
| power  | **−2.87 %** (−14.5)   | **−3.04 %** (−15.0)   | −3.2 % (−15.6)   | N = 1     |

The 2×2 grid itself measures 20495.33 µm² (top-level glue 1.254 µm²) and **4.19 mW** against baseline-BFP's 4.27, with all 875 273 pins annotated and none unannotated. On area this is the second-best grid in the project, but the power lever is a fifth of the bit-plane-B one: per mode at 8×8 the margin runs from **+5.60 % (mode 1)** and +4.32 % (mode 5) — the two whole-int4 modes, where the baseline's third Booth row is already a constant zero — through −0.81 % (7), −1.49 % (3), −3.67 % (10), −3.82 % (2), −3.86 % (11), −4.23 % (6) to **−6.08 / −6.28 / −6.35 % (modes 8, 9, 12)**: 9 of 11 wins, mean −2.42 % (16×16: mean −2.58 %, worst +5.58 %, best −6.55 %). See [Synthesis Area](../experiments/syn_area.md), [Synthesis Power](../experiments/syn_pwr.md), [Per-Mode Synthesis Power](../experiments/syn_mode_pwr.md) and [Grid Scaling](../experiments/syn_scaling.md).

The clock is unchanged: post-synthesis STA closes [pe_nr4sd_bfp](../modules/pe_nr4sd_bfp.md) at **493 MHz** (2000.2 ps path + 28.2 ps setup) against `pe_bfp`'s 494 MHz and `pe_bpl_b_bfp`'s 484 MHz — the critical path is the accumulator's carry chain in all three, not the DP8, so the two-digit leaf buys area and power but no frequency.

A first build recoded each nibble into **three** NR4SD⁺ digits (48-bit B bus per DP8) and came out at +0.5 % area / +9.9 % power at 8×8; the two-digit hybrid on this page superseded it.

## Parameters

| Parameter | Default | Description                                                                    |
| --------- | ------- | ------------------------------------------------------------------------------ |
| `N`       | 2       | Grid side — the array is `N × N` PEs. Chip target 8×8; a single PE is `N = 1`. |

## Interface

**Identical, port for port, to [top_NxN_bfp](./top_NxN_bfp.md)** — the recoded operand contract is entirely internal:

| Signal                                    | Dir | Description                                                                    |
| ----------------------------------------- | --- | ------------------------------------------------------------------------------ |
| `clk_i` / `rst_ni`                        | in  | Clock, asynchronous active-low reset.                                          |
| `in_a_i[0:N-1]` / `in_b_i[0:N-1]`         | in  | 256-bit mantissa operand per row / per column.                                 |
| `in_exp_a_i[0:N-1]` / `in_exp_b_i[0:N-1]` | in  | Per-row A format exponents (4 × 6-bit) / per-column B (4 × 2 × 6-bit).         |
| `mode_i`                                  | in  | Operating mode (4-bit), decoded once by the shared `ctrl`.                     |
| `sel_acc_i`                               | in  | Seed vs feedback for every PE's accumulator.                                   |
| `acc_i` / `acc_exp_i`                     | in  | Per-PE, per-lane accumulator seed mantissa and scale.                          |
| `en_row_i[0:N-1]` / `en_col_i[0:N-1]`     | in  | Row / column enables — scale the active region to any `rows × cols` rectangle. |
| `out_q_o` / `out_exp_o`                   | out | Per-PE, per-lane raw un-normalized result mantissa and scale.                  |

## Instantiation

```systemverilog
top_NxN_nr4sd_bfp #(.N(8)) top_NxN_nr4sd_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .in_a_i(in_a), .in_b_i(in_b),
    .in_exp_a_i(in_exp_a), .in_exp_b_i(in_exp_b),
    .mode_i(mode), .sel_acc_i(sel_acc),
    .acc_i(acc), .acc_exp_i(acc_exp),
    .en_row_i(en_row), .en_col_i(en_col),
    .out_q_o(out_q), .out_exp_o(out_exp)
);
```

## Composition

Against [top_NxN_bfp](./top_NxN_bfp.md) exactly **two instances change** — the same two the bit-plane-A build changes, on the same (column) side, and the mirror image of bit-plane B:

| per    | `top_NxN_bfp`                                 | `top_NxN_bpl_b_bfp`                      | `top_NxN_nr4sd_bfp`                      |
| ------ | --------------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| grid   | `ctrl`, `sel_acc` pipeline                    | same                                     | same                                     |
| row    | `disp_array_a`, `disp_array_exp_a_bfp`, `icg` | **`disp_array_a_bpl_b_bfp`**, same, same | same (the **plain** `disp_array_a`)      |
| column | `disp_array_b`, `disp_array_exp_b_bfp`, `icg` | same                                     | **`disp_array_b_nr4sd_bfp`**, same, same |
| tile   | `pe_bfp`, `icg`                               | **`pe_bpl_b_bfp`**, same                 | **`pe_nr4sd_bfp`**, same                 |

Each column dispatcher now emits two buses — the 16-bit NR4SD⁺ codes and the 24-bit Booth windows per DP8, 40 bits against raw B's 32 (+25 %) — both broadcast along the column; raw B never reaches a PE. The row route is the plain [disp_array_a](../modules/disp_array_a.md). Clock-gating structure, pipeline depth and the `en_row`/`en_col` rectangle scaling are untouched:

```systemverilog
disp_array_b_nr4sd_bfp disp_array_b_nr4sd_bfp_i (
    .clk_i    (clk_b),
    .rst_ni   (rst_ni),
    .pe_in_b_i(in_b_i[c]),
    .sel_b_i  (sel_b),
    .ctr_l_i  (ctr_l),
    .ctr_h_i  (ctr_h),
    .is_signed_b_i(is_signed_b),
    .b_nr4sd_dp8_o(b_nr4sd_dp8_col[c]),
    .b_booth_dp8_o(b_booth_dp8_col[c])
);
```

### Where `is_signed_b` goes

`ctrl` is unchanged — it still emits `is_signed_b` per DP8 — but its consumer has moved: the flag feeds the **N column dispatchers** and never reaches the N² PEs, whose only signedness port is `is_signed_a_i`. Inside the dispatcher every nibble is recoded **as signed**, and `is_signed_b[i]` reads as "DP8 i holds the top nibble of its element": it selects the cross-nibble carry that the DP8 *below* it in index imports, one AND per lane —

```
c_in[i][e] = ~is_signed_b_i[i+1] & gated_nibble[i+1][e][3]
```

— with no link into DP8 `4q+3`, which is always the bottom of its element. A lower nibble read as signed is off by `−16·b₃·A`; the nibble above gains `+b₃·A` through the carry; the ×16 weight of the L1 merge in the PE tree cancels the two, element by element, whatever the grouping of the DP8s (see the [derivation](../../doc/formulas/encodings/nr4sd_2pp.tex) and [pe_array_nr4sd_bfp](../modules/pe_array_nr4sd_bfp.md)). This is the only control-fanout change in the grid — bit-plane B does the same with `is_signed_a`.

### No idle mask

The bit-plane-B top level has to clear `is_signed_b` for idle DP8s (`gen_idle_mask`), because its DP8's weight-2³ correction turns a zero operand into a non-canonical carry-save zero. This grid needs **no such logic**: an idle DP8's gated nibble is zero, so its link bit is zero whatever its flag — the link reads the *gated* nibble, after `gate_b_n` — and a zero nibble recodes to digit 0 on both cells, so the leaf returns an exact, canonical zero pair. Both sides of an idle DP8's exponent are already gated to zero by the exponent dispatchers, as in `top_NxN_bfp`, so its scale never wins a max.

### Modes 2 and 6 with unequal block exponents

One behavioural caveat, and it is a property of the tree, not of the dispatcher. At L0 the two halves of a B element sit in different nodes (DP8 `4q` pairs with `4q+2`, `4q+1` with `4q+3`), so the `±16·b₃·A` cross-nibble terms pass through the L0 aligners **before** L1 recombines the nibbles. With equal exponents every aligner is transparent and the cancellation at L1 is exact — the grid is bit-identical to `top_NxN_bfp`. With unequal exponents inside an L0 node, each term is truncated on its own side, and the result is no longer bit-identical to the three-partial-product tree: an LSB-level difference with the same error bound. The mode tables allow unequal exponents within an L0 node only in **modes 2 and 6**; all other modes, and all modes with equal exponents, are value-identical.

## Verification

[tb_top_NxN_nr4sd_bfp](../testbenches/tb_top_NxN_nr4sd_bfp.md) drives the grid at **full pipeline throughput** with distinct A per row and B per column, over three streaming patterns (single-shot, accumulation, rectangle scaling) × 11 modes × two exponent experiments. **66/66, N = 2, 0 mismatches**, `-Wall` clean. [tb_top_NxN_nr4sd_bfp_pwr](../../tb/tb_top_NxN_nr4sd_bfp_pwr.sv) supplies the VCD stimulus for the power experiments.

Source: [top_NxN_nr4sd_bfp.sv](../../rtl/top_NxN_nr4sd_bfp.sv) — Testbench: [tb_top_NxN_nr4sd_bfp.sv](../../tb/tb_top_NxN_nr4sd_bfp.sv) — Diagram: [top_NxN_nr4sd_bfp](../../doc/diagrams/top_NxN_nr4sd_bfp.excalidraw) — Derivation: [nr4sd_2pp.tex](../../doc/formulas/encodings/nr4sd_2pp.tex)
