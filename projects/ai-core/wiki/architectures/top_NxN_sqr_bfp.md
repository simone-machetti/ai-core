# PE Grid (Square-BFP)

`top_NxN_sqr_bfp` — the **square-BFP** N × N grid of Processing Elements: the [top_NxN_sqr](./top_NxN_sqr.md) analogue with the BFP exponent sideband, or [top_NxN_bfp](./top_NxN_bfp.md) with the square datapath. It tiles N² [pe_sqr_bfp](../modules/pe_sqr_bfp.md) cores, sharing operand A (mantissa + exponent) along each row and B along each column, so PE[r][c] evaluates `A[r] · B[c]` in block floating point via the square identity. **Same external interface and behaviour as `top_NxN_bfp`** — all the square-BFP machinery is internal (see [BFP_imp.md](../../doc/BFP_imp.md) §9).

## Purpose

The multiply→square amortization applies exactly as in `top_NxN_sqr`: the α correction is A-only (shared per **row**), β is B-only (shared per **column**), so the grid needs only **N α + N β** generators feeding N² PEs. All redundant control/dispatch/const is hoisted and shared:

- **[ctrl_sqr](../modules/ctrl_sqr.md)** — one instance decodes the grid-wide mode into every control, **reused verbatim** (no `ctrl_sqr_bfp`): it already drops `ctr_l`/`ctr_h` and emits the `zero` the BFP exp dispatchers need; `sel_const` simply goes unused because the constant is per-DP8 upstream.
- **[const_sqr_bfp](../modules/const_sqr_bfp.md)** — one combinational instance holds the per-DP8 constant `C_j`; its 4-bit `mode` input is registered **once ahead** of it so the constant meets the singly-registered dispatched operands at the L0 combine — **one register fewer** than `const_sqr`, which reaches the later acc stage.
- Per **row**: **[disp_array_a_sqr](../modules/disp_array_a_sqr.md) + [disp_array_exp_a_sqr_bfp](../modules/disp_array_exp_a_sqr_bfp.md) + [pe_array_alpha_sqr_bfp](../modules/pe_array_alpha_sqr_bfp.md)** share the row clock-gate — the dispatched A mantissa/exponent and, combinationally from the registered A, the `−α` taps freeze together when the row is off.
- Per **column**: **[disp_array_b_sqr](../modules/disp_array_b_sqr.md) + [disp_array_exp_b_sqr_bfp](../modules/disp_array_exp_b_sqr_bfp.md) + [pe_array_beta_sqr_bfp](../modules/pe_array_beta_sqr_bfp.md)** share the column clock-gate.
- **[pe_sqr_bfp](../modules/pe_sqr_bfp.md)[r][c]** — fed the row's A/`−α`/exp-A, the column's B/`−β`/exp-B, the shared `const_dp8` and controls.

The α/β generators are **tree-less and combinational** (their pipeline register lives in `pe_array_sqr_bfp`'s L0); fed by the clock-gated dispatch register they still freeze with their row/column.

**Clock gating / scaling:** identical to `top_NxN_bfp` — `en_row_i` / `en_col_i` (active-high) select an enabled rectangle; a PE runs when `en_row[r] & en_col[c]`. One [icg](../modules/icg.md) per row (dispatch A + exp + α), one per column (dispatch B + exp + β), one per PE. `ctrl_sqr`, the const pipeline and the `sel_acc` pipeline run ungated. The raw accumulator mantissa (`out_q_o`) and its 7-bit product-domain scale (`out_exp_o`) leave un-normalized; `out_exp_o` shares the `acc_exp_i` seed format, so an output can feed straight back as a seed. Each PE output is valid **3 clocks** after its operands.

## Parameters

| Parameter | Default | Description                                                         |
| --------- | ------- | ------------------------------------------------------------------- |
| `N`       | `2`     | Grid side; the array is N × N PEs (chip: N = 8; single PE = N = 1). |

## Interface

Identical to [top_NxN_bfp](./top_NxN_bfp.md): `clk_i`, `rst_ni`, `in_a_i[N]` / `in_exp_a_i[N]` (per-row A mantissa + exponent), `in_b_i[N]` / `in_exp_b_i[N]` (per-col B mantissa + exponent), `mode_i` (4-bit), `sel_acc_i`, `acc_i[N][N][8]` / `acc_exp_i[N][N][8]` (per-PE seed + scale), `en_row_i[N]`, `en_col_i[N]`, `out_q_o[N][N][8]` / `out_exp_o[N][N][8]`.

## Verification

[tb_top_NxN_sqr_bfp](../../tb/tb_top_NxN_sqr_bfp.sv) is a streaming bench with an independent software golden — distinct A per row / B per column driven at full pipeline throughput and checked against a pipeline-delayed reference — held to the **same standard as baseline BFP** (both exponent experiments, both checks):

- **Equal-exp** = black-box **bit-exact matmul** `A·B` with `exp = 2·base` — exercises the full grid (row/col fan-out, per-PE accumulate, streaming, clock-gating/scaling, `const_sqr_bfp`, and the whole mantissa datapath with the aligners transparent).
- **Distinct-exp** = an **exponent check** `out_exp === egold` (fan-out + max-tree) **and** a from-operands **mantissa window** (the square places the same operands into the same DP8s, the L0 block-negate reproduces the multiply's baked-in sign, each bundle resolving to `2·(signed product)`; the window feeds `2·dp8_gold` at L0 with the per-bundle L0 truncation slack and the `½` at read time). A negative control (window centre at `1·` instead of `2·`) fails all distinct-exp cases while equal-exp stays clean, confirming the check is live and tight.

Three streaming passes each — single-shot, accumulation (`seed + Σ` of distinct tiles), and rectangle scaling via `en_row`/`en_col`. N=2, **66/66, 0 mismatches**. The streaming check is what proves the shared `−α`/`−β` generator pipelines stay aligned with each PE's product cycle-by-cycle.

Source: [top_NxN_sqr_bfp.sv](../../rtl/top_NxN_sqr_bfp.sv) — Testbench: [tb_top_NxN_sqr_bfp.sv](../../tb/tb_top_NxN_sqr_bfp.sv) — Diagram: [top_NxN_sqr_bfp](../../doc/diagrams/top_NxN_sqr_bfp.excalidraw)
