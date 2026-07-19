# Processing Element (Square)

`pe_sqr` — the square variant of the per-PE core [pe](./pe.md). Like `pe` it chains [pe_array_sqr](./pe_array_sqr.md) → [acc_array_sqr](./acc_array_sqr.md) plus the two acc pipeline registers, and masks the operands with `en_i`. The difference: the α/β corrections are computed by the shared row/column generators outside the PE, so their `−α`/`−β` carry-save taps arrive as **inputs** (pre-aligned), and the per-mode constant comes from the shared [const_sqr](./const_sqr.md).

## Purpose

`pe_sqr` holds **only** `pe_array_sqr`, `acc_array_sqr` and the two acc registers — everything shared (dispatch, control, const, α/β generators) lives in the grid [top_NxN_sqr](../architectures/top_NxN_sqr.md). It receives the dispatched operands `a_dp8`/`b_dp8`, the row's `−α` taps, the column's `−β` taps, and `c`/`c_neg`, and drives eight 20-bit outputs.

**Operand isolation:** `en_i` AND-masks *every* per-cycle datapath input — both dispatched operands **and** the `−α`/`−β` tap buses — to zero, so a clock-gated PE is fully quiet (the PE clock is gated externally by the same enable). `c`/`c_neg` (mode-constant) and `acc` (clock-gated regs) hold on their own and need no mask.

**Pipeline:** identical depth to `pe` — one `pe_array_sqr` L0 register and one `acc_array_sqr` output register inside (the disp input register is outside). `acc_i` is pipelined by two registers to meet the tap at the acc stage; the `−α`/`−β` taps (the generators have the same depth as `pe_array_sqr`), `c`/`c_neg` and the acc-stage selects arrive already aligned.

## Interface

| Signal                                               | Dir | Width   | Description                                                    |
| ---------------------------------------------------- | --- | ------- | -------------------------------------------------------------- |
| `clk_i` / `rst_ni`                                   | in  | 1       | Clock (externally gated) / async reset.                        |
| `a_dp8_i` / `b_dp8_i`                                | in  | 64 / 32 | Dispatched operands (16 DP8s), from `disp_array_*_sqr`.        |
| `en_i`                                               | in  | 1       | Operand + tap isolation mask (and external clock-gate enable). |
| `neg_i` / `sel_shift_i`                              | in  | 6 / 3   | `pe_array_sqr` controls (block-negate, tree shifts).           |
| `a_l0..l3_{sum,carry}_i`                             | in  | 19…39   | `−α` taps, from `pe_array_alpha_sqr` (row).                    |
| `b_l0..l3_{sum,carry}_i`                             | in  | 19…39   | `−β` taps, from `pe_array_beta_sqr` (column).                  |
| `c_i` / `c_neg_i`                                    | in  | 32 / 8  | Per-mode constant, from `const_sqr`.                           |
| `acc_i`                                              | in  | 20×8    | Per-PE external accumulator seed.                              |
| `sel_out_i`/`sel_acc_i`/`sel_const_i`/`prop_carry_i` | in  | 2/1/2/1 | acc-stage controls.                                            |
| `out_o`                                              | out | 20×8    | Per-lane results (`pe_out`).                                   |

## Examples

```systemverilog
pe_sqr pe_sqr_i (
    .clk_i(clk_pe), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8_row), .b_dp8_i(b_dp8_col), .en_i(en_pe),
    .neg_i(neg), .sel_shift_i(sel_shift),
    .a_l0_sum_i(arow_l0_sum), /* … row −α taps … */
    .b_l0_sum_i(bcol_l0_sum), /* … col −β taps … */
    .c_i(c_q2), .c_neg_i(cn_q2), .acc_i(acc_word),
    .sel_out_i(sel_out), .sel_acc_i(selacc_q2),
    .sel_const_i(sel_const), .prop_carry_i(prop_carry),
    .out_o(out_q)
);
```

Exercised inside [tb_top_NxN_sqr](../testbenches/tb_top_NxN_sqr.md); there is no standalone `pe_sqr` bench (as with the baseline `pe`).

Source: [pe_sqr.sv](../../rtl/pe_sqr.sv)
