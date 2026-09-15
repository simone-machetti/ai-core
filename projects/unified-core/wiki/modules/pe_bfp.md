# Processing Element (BFP)

`pe_bfp` — the BFP variant of the per-PE core [pe](./pe.md). Like `pe` it chains operand isolation → [pe_array_bfp](./pe_array_bfp.md) → [acc_array_bfp](./acc_array_bfp.md) plus the two acc pipeline registers, and masks the operands with `en_i`. The difference is the **exponent sideband**, threaded exactly parallel to the mantissa path: the dispatched exponents are masked and fed to `pe_array_bfp`, and a twin acc-exponent pipeline delivers the seed scale to `acc_array_bfp`.

## Purpose

`pe_bfp` holds only `pe_array_bfp`, `acc_array_bfp` and the acc pipeline registers — everything shared (control, mantissa and exponent dispatch) lives in the grid [top_NxN_bfp](../architectures/top_NxN_bfp.md). It receives the dispatched mantissa operands `a_dp8`/`b_dp8`, the dispatched per-DP8 exponents `exp_a_dp8`/`exp_b_dp8`, the per-PE seed `acc`/`acc_exp`, and drives eight 20-bit mantissa outputs plus their 7-bit scales.

**Operand isolation:** `en_i` AND-masks *every* shared per-cycle input — both mantissa operands **and** both exponent operands — to zero. The PE clock is gated externally by the same enable, so the mask keeps the `pe_array_bfp` logic before the first PE register (the still-toggling shared dispatch that feeds the multipliers and the exponent add) quiet while gated. Zeroed exponents are the minimum scale, so a masked DP8 never wins an alignment max. `acc`/`acc_exp` (per-PE, clock-gated regs) hold on their own and need no mask.

**Pipeline:** identical depth to `pe` — one `pe_array_bfp` L0 register and one `acc_array_bfp` output register inside (the disp input register is upstream, in the grid). `acc_i` is delayed by two registers to meet the tap at the acc stage, and `acc_exp_i` by a **twin pair** of registers so the seed scale meets the tap scale at the accumulator. `sel_out`, `sel_acc` and `prop_carry` arrive already aligned. The raw accumulator mantissa and scale leave un-normalized on `out_o` / `out_exp_o`.

## Interface

| Signal                                 | Dir | Width   | Description                                                         |
| -------------------------------------- | --- | ------- | ------------------------------------------------------------------- |
| `clk_i` / `rst_ni`                     | in  | 1       | Clock (externally gated) / async reset.                             |
| `a_dp8_i` / `b_dp8_i`                  | in  | 64 / 32 | Dispatched mantissa operands (16 DP8s), from `disp_array_*`.        |
| `exp_a_dp8_i` / `exp_b_dp8_i`          | in  | 6 / 6   | Dispatched per-DP8 exponents, from `disp_array_exp_*_bfp`.          |
| `en_i`                                 | in  | 1       | Operand + exponent isolation mask (and external clock-gate enable). |
| `is_signed_a_i` / `is_signed_b_i`      | in  | 1 each  | Per-DP8 signedness, from `ctrl`.                                    |
| `sel_shift_i`                          | in  | 3       | `pe_array_bfp` tree shift enables.                                  |
| `en_level_i`                           | in  | 3       | Tree operand-isolation enables — masks levels below the tap.        |
| `acc_i`                                | in  | 20×8    | Per-PE external accumulator seed (mantissa).                        |
| `acc_exp_i`                            | in  | 7×8     | Per-PE external seed scale (product-domain).                        |
| `sel_out_i`/`sel_acc_i`/`prop_carry_i` | in  | 2/1/1   | acc-stage controls.                                                 |
| `out_o`                                | out | 20×8    | Per-lane result mantissas (`pe_out`).                               |
| `out_exp_o`                            | out | 7×8     | Per-lane running accumulator scales (`pe_exp`).                     |

## Examples

```systemverilog
pe_bfp pe_bfp_i (
    .clk_i(clk_pe), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8_row), .b_dp8_i(b_dp8_col),
    .exp_a_dp8_i(exp_a_dp8_row), .exp_b_dp8_i(exp_b_dp8_col),
    .en_i(en_pe),
    .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
    .sel_shift_i(sel_shift), .en_level_i(en_level),
    .acc_i(acc_word), .acc_exp_i(acc_exp_word),
    .sel_out_i(sel_out), .sel_acc_i(selacc_q2), .prop_carry_i(prop_carry),
    .out_o(out_q), .out_exp_o(out_exp_q)
);
```

## Internal logic

Four AND-masks isolate the shared dispatch — the two mantissa buses and the two exponent buses — before they reach `pe_array_bfp`:

```systemverilog
for (d = 0; d < NUM_DP8; d++) begin : gen_mask
    assign a_dp8_m[d]     = a_dp8_i[d]     & {A_DP8_WIDTH{en_i}};
    assign b_dp8_m[d]     = b_dp8_i[d]     & {B_DP8_WIDTH{en_i}};
    assign exp_a_dp8_m[d] = exp_a_dp8_i[d] & {EXP_IN_WIDTH{en_i}};
    assign exp_b_dp8_m[d] = exp_b_dp8_i[d] & {EXP_IN_WIDTH{en_i}};
end
```

Two twin [reg_n](./reg_n.md) chains then delay the per-PE seed to the acc stage — one for the mantissa (`acc_q1` → `acc_q2`), one for the scale (`acc_exp_q1` → `acc_exp_q2`) — after which `pe_array_bfp` reduces the masked operands into the carry-save-plus-scale taps and `acc_array_bfp` resolves, aligns and accumulates them, driving `out_o` / `out_exp_o`. `out_o` is valid 3 clocks after the operands and mode are applied.

Exercised inside [tb_top_NxN_bfp](../../tb/tb_top_NxN_bfp.sv); there is no standalone `pe_bfp` bench (as with the baseline `pe` and `pe_sqr`).

Source: [pe_bfp.sv](../../rtl/pe_bfp.sv) — Diagram: [pe_bfp](../../doc/diagrams/pe_bfp.excalidraw)
