# PE Grid (Square)

`top_NxN_sqr` — the **square** N × N grid of Processing Elements, the [top_NxN](./top_NxN.md) analogue. It tiles N² [pe_sqr](../modules/pe_sqr.md) cores, sharing operand A along each row and B along each column, so PE[r][c] evaluates `A[r] · B[c]`. **Same external interface and behaviour as `top_NxN`** — all the square machinery is internal — so it is bit-exact to the baseline grid and reuses its testbench.

## Purpose

The multiply→square amortization shows up here: the α correction is A-only (shared per **row**), β is B-only (shared per **column**), so the grid needs only **N α + N β** generators feeding N² PEs. All the redundant control/dispatch/const is hoisted and shared:

- **[ctrl_sqr](../modules/ctrl_sqr.md)** — one instance decodes the grid-wide mode into every control.
- **[const_sqr](../modules/const_sqr.md)** — one instance holds the per-mode constant; its 4-bit `mode` input is registered **once ahead** of it and its `c`/`c_neg` outputs **once after**, so the constant meets the tap at the acc stage in the same two register delays with **one register fewer** than registering the wide outputs twice.
- Per **row**: **[disp_array_a_sqr](../modules/disp_array_a_sqr.md) + [pe_array_alpha_sqr](../modules/pe_array_alpha_sqr.md)** share the row clock-gate — the dispatched A and the `−α` taps freeze together when the row is off.
- Per **column**: **[disp_array_b_sqr](../modules/disp_array_b_sqr.md) + [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md)** share the column clock-gate.
- **[pe_sqr](../modules/pe_sqr.md)[r][c]** — fed the row's A/`−α`, the column's B/`−β`, and the shared const/controls.

**Clock gating / scaling:** `en_row_i` / `en_col_i` (active-high) select an enabled rectangle; a PE runs when `en_row[r] & en_col[c]`. One [icg](../modules/pe.md) per row (dispatch A + α), one per column (dispatch B + β), one per PE. `ctrl_sqr`, the const pipeline and the `sel_acc` pipeline run ungated. Each PE output is valid **3 clocks** after its operands.

## Parameters

| Parameter | Default | Description                                                         |
| --------- | ------- | ------------------------------------------------------------------- |
| `N`       | `2`     | Grid side; the array is N × N PEs (chip: N = 8; single PE = N = 1). |

## Interface

Identical to [top_NxN](./top_NxN.md): `clk_i`, `rst_ni`, `in_a_i[N]` (per-row A), `in_b_i[N]` (per-col B), `mode_i` (4-bit), `sel_acc_i`, `acc_i[N][N][8]` (per-PE seed), `en_row_i[N]`, `en_col_i[N]`, `out_q_o[N][N][8]`.

## Verification

[tb_top_NxN_sqr](../testbenches/tb_top_NxN_sqr.md) reuses the baseline `tb_top_NxN` streaming bench verbatim (the square grid is bit-exact and shares the interface): distinct A per row / B per column, driven at **full pipeline throughput** (a fresh operand every clock) and checked against a pipeline-delayed golden. All 11 modes, three streaming passes — single-shot, accumulation (`seed + Σ` of `NUM_ACC` distinct tiles), and rectangle scaling via `en_row`/`en_col`. N=2, 0 mismatches, `-Wall` clean. The streaming check is what proves the shared −α/−β generator pipelines stay aligned with each PE's product cycle-by-cycle.

Source: [top_NxN_sqr.sv](../../rtl/top_NxN_sqr.sv)
