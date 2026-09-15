# PE Grid (BFP)

`top_NxN_bfp` — the **BFP** N × N grid of Processing Elements, the [top_NxN](./top_NxN.md) analogue. It tiles N² [pe_bfp](../modules/pe_bfp.md) cores, sharing operand A (mantissa + exponent) along each row and B along each column, so PE[r][c] evaluates `A[r] · B[c]` in block floating point. It reuses `top_NxN`'s control, dispatch, clock-gating and pipeline unchanged, adding only the exponent sideband next to the mantissa path.

## Purpose

BFP rides on top of the integer grid as a pure exponent sideband: the mantissa datapath is `top_NxN` verbatim, and the exponent dispatchers slot in **parallel to the mantissa dispatchers, under the same gated clocks**. All the redundant control/dispatch is hoisted and shared exactly as in the baseline:

- **[ctrl](../modules/ctrl.md) — unchanged.** The exponent path reuses `sel_a`/`sel_b`/`ctr_l`/`ctr_h`, and the tree/accumulator reuse `sel_shift`/`en_level`/`sel_out`/`prop_carry`, so BFP needs **no new decode** — the aligners self-activate on unequal exponents.
- Per **row**: **[disp_array_a](../modules/disp_array_a.md) + [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md)** share the row clock-gate (`clk_a`) — the dispatched A mantissa and the A exponent freeze together when the row is off.
- Per **column**: **[disp_array_b](../modules/disp_array_b.md) + [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md)** share the column clock-gate (`clk_b`).
- **`sel_acc`** — pipelined once here (two registers, shared), as in the baseline.
- **[pe_bfp](../modules/pe_bfp.md)[r][c]** — fed the row's A/`exp_a`, the column's B/`exp_b`, and the per-PE `acc`/`acc_exp`. The A and B exponents come from different instances (row vs column) and first meet inside the PE, where `pe_array_bfp` forms the per-DP8 scale `e_A + e_B`.

**Exponent source words.** `in_exp_a_i[r]` is 4 blocks × 6-bit (one exponent per 64-bit A block, the source rule); `in_exp_b_i[c]` is 4 blocks × 12-bit (the two 32-bit-half exponents of each B block — B can pack halves of two source blocks). The raw accumulator mantissa (`out_q_o`) and its 7-bit product-domain scale (`out_exp_o`) leave **un-normalized**; `out_exp_o` shares the `acc_exp_i` seed format, so an output can feed straight back as a seed.

**Clock gating / scaling:** identical to [top_NxN](./top_NxN.md). `en_row_i` / `en_col_i` (active-high) select an enabled rectangle; a PE runs when `en_row[r] & en_col[c]`. One [icg](../modules/icg.md) per row (dispatch A + exp A), one per column (dispatch B + exp B), one per PE — the PE ICG both gates the clock and masks the operands (mantissa **and** exponent). `ctrl` and the `sel_acc` pipeline run ungated. Each PE output is valid **3 clocks** after its operands.

## Parameters

| Parameter | Default | Description                                                         |
| --------- | ------- | ------------------------------------------------------------------- |
| `N`       | `2`     | Grid side; the array is N × N PEs (chip: N = 8; single PE = N = 1). |

Derived `localparam`s add the exponent widths to the baseline set: `EXP_IN_WIDTH = 6` (stored format exponent), `EXP_WIDTH = 7` (product-domain scale), `EXP_A_WIDTH = 24` (`4 × 6`, the A word), `EXP_B_WIDTH = 48` (`4 × 2 × 6`, the B word), alongside `PE_IN_WIDTH = 256`, `MODE_WIDTH = 4`, `NUM_LANE = 8`, `PE_WIDTH = 20`.

## Interface

[top_NxN](./top_NxN.md)'s interface plus the exponent sideband:

| Signal                                | Dir | Width    | Description                                             |
| ------------------------------------- | --- | -------- | ------------------------------------------------------- |
| `clk_i`, `rst_ni`                     | in  | 1        | Clock and asynchronous active-low reset (ungated).      |
| `in_a_i[0:N-1]`                       | in  | 256 each | Operand A mantissa, one per row.                        |
| `in_b_i[0:N-1]`                       | in  | 256 each | Operand B mantissa, one per column.                     |
| `in_exp_a_i[0:N-1]`                   | in  | 24 each  | A exponents, one per row (4 blocks × 6-bit).            |
| `in_exp_b_i[0:N-1]`                   | in  | 48 each  | B exponents, one per column (4 blocks × 12-bit, H/L).   |
| `mode_i`                              | in  | 4        | Operating mode, broadcast to all PEs.                   |
| `sel_acc_i`                           | in  | 1        | Accumulate select, broadcast to all PEs.                |
| `acc_i[0:N-1][0:N-1][0:7]`            | in  | 20 each  | External accumulator seed mantissa, per PE (8 lanes).   |
| `acc_exp_i[0:N-1][0:N-1][0:7]`        | in  | 7 each   | External seed scale (product-domain), per PE.           |
| `en_row_i[0:N-1]`                     | in  | 1 each   | Active-high row enable.                                 |
| `en_col_i[0:N-1]`                     | in  | 1 each   | Active-high column enable.                              |
| `out_q_o[0:N-1][0:N-1][0:7]`          | out | 20 each  | Per-PE registered result mantissa (8 lanes).            |
| `out_exp_o[0:N-1][0:N-1][0:7]`        | out | 7 each   | Per-PE running accumulator scale (8 lanes).             |

## Instantiation

```systemverilog
top_NxN_bfp #(.N(8)) grid_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .in_a_i(in_a), .in_b_i(in_b),
    .in_exp_a_i(in_exp_a), .in_exp_b_i(in_exp_b),
    .mode_i(mode), .sel_acc_i(sel_acc),
    .acc_i(acc), .acc_exp_i(acc_exp),
    .en_row_i(en_row), .en_col_i(en_col),
    .out_q_o(out_q), .out_exp_o(out_exp)
);
```

## Verification

[tb_top_NxN_bfp](../../tb/tb_top_NxN_bfp.sv) drives the grid at **full pipeline throughput** (a fresh operand every clock, checked against a pipeline-delayed golden) with distinct A per row / B per column, in two exponent experiments each covering three streaming passes — single-shot, accumulation (`seed + Σ` of distinct tiles), and rectangle scaling via `en_row`/`en_col`. **Equal-exponent** runs as a black-box bit-exact matmul `A · B` (with `out_exp = 2·base`), proving the whole mantissa grid — fan-out, per-PE accumulate, clock-gating/scaling — is untouched with the aligners transparent. **Distinct-exponent** checks the exponent max-tree (`out_exp === egold`) and a from-operands aligned window against an independent golden. N=2, 0 mismatches, `-Wall` clean.

Source: [top_NxN_bfp.sv](../../rtl/top_NxN_bfp.sv) — Testbench: [tb_top_NxN_bfp.sv](../../tb/tb_top_NxN_bfp.sv) — Diagram: [top_NxN_bfp](../../doc/diagrams/top_NxN_bfp.excalidraw)
