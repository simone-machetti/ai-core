# Processing Element (Square-BFP)

`pe_sqr_bfp` — the per-PE core of the square-BFP grid: [pe_bfp](./pe_bfp.md) with the square front-end, or equivalently [pe_sqr](./pe_sqr.md) with the BFP exponent sideband. Like both it chains [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) → [acc_array_sqr_bfp](./acc_array_sqr_bfp.md) plus the acc pipeline registers, and masks its operands with `en_i`. The difference from `pe_sqr`: the α/β corrections **and** the per-DP8 constant are folded at L0 upstream, so the accumulator takes **one tap set** (no `C`/`c_neg`), and every operand carries a BFP exponent sideband.

## Purpose

`pe_sqr_bfp` holds **only** `pe_array_sqr_bfp`, `acc_array_sqr_bfp` and the acc/acc-exp pipeline registers — everything shared (dispatch, control, const, α/β generators) lives in the grid [top_NxN_sqr_bfp](../architectures/top_NxN_sqr_bfp.md). It receives the dispatched mantissa operands `a_dp8`/`b_dp8` and their exponents `exp_a_dp8`/`exp_b_dp8`, the row's `−α` and column's `−β` per-DP8 carry-save pairs, and the shared per-DP8 `const_dp8` from [const_sqr_bfp](./const_sqr_bfp.md). Because `pe_array_sqr_bfp` combines `PE − α − β + C` at L0 (under each block's scale) and delivers a single `2·P` tap set, `acc_array_sqr_bfp` sees one operand and no constant ports — the reason this PE, unlike `pe_sqr`, drives no `c`/`c_neg`.

**Operand isolation:** `en_i` AND-masks *every* per-cycle datapath input — the dispatched mantissa operands (`a_dp8`/`b_dp8`), the dispatched **exponents** (`exp_a_dp8`/`exp_b_dp8`) and the `−α`/`−β` carry-save buses — to zero, so a clock-gated PE stays quiet while the still-toggling shared dispatch/generators change under it:

```systemverilog
assign a_dp8_m[d]     = a_dp8_i[d]     & {A_DP8_WIDTH{en_i}};
assign exp_a_dp8_m[d] = exp_a_dp8_i[d] & {EXP_IN_WIDTH{en_i}};
assign alpha_sum_m[d] = alpha_sum_i[d] & {DP8_WIDTH{en_i}};   // …and b, exp_b, alpha_carry, beta_{sum,carry}
```

Zeroed exponents are the **minimum scale**, so a masked DP8 never wins an alignment max. `const_dp8`, `neg`, `zero` (mode constants/controls) and `acc`/`acc_exp` (clock-gated regs) hold on their own and need no mask.

**Pipeline:** identical depth to `pe_bfp` — 3 stages (the disp input register upstream, one `pe_array_sqr_bfp` L0 register, one `acc_array_sqr_bfp` output register). `acc_i` **and** `acc_exp_i` are each pipelined by two registers here to meet the tap at the acc stage; the `−α`/`−β` taps, `const_dp8` and the acc-stage selects (`sel_out`, `sel_acc`, `prop_carry`) arrive already aligned from the shared `ctrl_sqr`.

```systemverilog
reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc1_i (.d_i(acc_i),  .q_o(acc_q1) …);
reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc2_i (.d_i(acc_q1), .q_o(acc_q2) …);   // acc_exp mirrors this pair
```

## Interface

| Signal                                    | Dir | Width   | Description                                                     |
| ----------------------------------------- | --- | ------- | -------------------------------------------------------------- |
| `clk_i` / `rst_ni`                        | in  | 1       | Clock (externally gated) / async reset.                        |
| `a_dp8_i` / `b_dp8_i`                      | in  | 64 / 32 | Dispatched mantissa operands (16 DP8s), from `disp_array_*_sqr`. |
| `exp_a_dp8_i` / `exp_b_dp8_i`             | in  | 6 ×16   | Dispatched per-DP8 exponents, from `disp_array_exp_*_sqr_bfp`.  |
| `alpha_sum_i` / `alpha_carry_i`           | in  | 18 ×16  | Per-DP8 `−α` carry-save pairs, from `pe_array_alpha_sqr_bfp` (row). |
| `beta_sum_i` / `beta_carry_i`             | in  | 18 ×16  | Per-DP8 `−β` carry-save pairs, from `pe_array_beta_sqr_bfp` (col).  |
| `const_dp8_i`                             | in  | 18 ×16  | Per-DP8 constant `C_j`, from `const_sqr_bfp`.                   |
| `en_i`                                     | in  | 1       | Operand + tap + exp isolation mask (and external clock-gate enable). |
| `en_level_i`                              | in  | 3       | Tree operand-isolation enables — masks levels below the tap.   |
| `neg_i` / `sel_shift_i`                    | in  | 6 / 3   | `pe_array_sqr_bfp` controls (block-negate, tree shifts).       |
| `zero_i`                                   | in  | 1 ×16   | Per-DP8 idle clean-zero (gates α/β/const of an idle DP8).      |
| `acc_i` / `acc_exp_i`                      | in  | 20×8 / 7×8 | Per-PE external accumulator seed and its scale.             |
| `sel_out_i`/`sel_acc_i`/`prop_carry_i`    | in  | 2/1/1   | acc-stage controls.                                            |
| `out_o` / `out_exp_o`                      | out | 20×8 / 7×8 | Per-lane results (`pe_out`) and running BFP scale.          |

## Instantiation

```systemverilog
pe_sqr_bfp pe_sqr_bfp_i (
    .clk_i(clk_pe), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8_row), .b_dp8_i(b_dp8_col),
    .exp_a_dp8_i(exp_a_row), .exp_b_dp8_i(exp_b_col),
    .alpha_sum_i(alpha_sum_row), .alpha_carry_i(alpha_carry_row), /* … β col taps … */
    .const_dp8_i(const_dp8), .en_i(en_pe),
    .en_level_i(en_level), .neg_i(neg), .zero_i(zero), .sel_shift_i(sel_shift),
    .acc_i(acc_word), .acc_exp_i(acc_exp_word),
    .sel_out_i(sel_out), .sel_acc_i(selacc_q2), .prop_carry_i(prop_carry),
    .out_o(out_q), .out_exp_o(out_exp_q)
);
```

Exercised inside [tb_top_NxN_sqr_bfp](../../tb/tb_top_NxN_sqr_bfp.sv); there is no standalone `pe_sqr_bfp` bench (as with the baseline `pe_bfp`).

Source: [pe_sqr_bfp.sv](../../rtl/pe_sqr_bfp.sv) — Diagram: [pe_sqr_bfp](../../doc/diagrams/pe_sqr_bfp.excalidraw)
