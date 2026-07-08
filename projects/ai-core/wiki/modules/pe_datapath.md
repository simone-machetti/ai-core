# PE Datapath

`pe_datapath` — the datapath wrapper of the PE. It chains the three datapath stages — [disp_array](./disp_array.md) → [pe_array](./pe_array.md) → [acc_array](./acc_array.md) — and exposes their control ports directly. It is purely structural: no logic, no registers of its own.

## Purpose

`pe_datapath` is the controlled datapath, factored out of [top_pe_bas](../architectures/top_pe_bas.md) so that the control decode and the control-path pipeline can sit around it. The carry-save taps between `pe_array` and `acc_array` are internal; everything else — the operands, all `disp`/`pe`/`acc` controls, the external accumulator word, and the outputs — is a port. Each stage keeps its own pipeline register (the `disp_array` operand input, the `pe_array` L0 node, the `acc_array` output), so the datapath is a 3-stage pipeline. The controls arrive already delayed to the right cycle by `top_pe_bas`; this wrapper only wires them.

## Parameters

None — fixed to the PE configuration; the shapes are baked in as `localparam`s (operand width 256, `NUM_DP8 = 16`, tap widths `18/29/37/38`, `NUM_LANE = 8`, `PE_WIDTH = 20`).

## Interface

| Signal                                | Dir | Width   | Description                              |
| ------------------------------------- | --- | ------- | ---------------------------------------- |
| `clk_i`, `rst_ni`                     | in  | 1       | Clock and asynchronous active-low reset. |
| `pe_in_a_i`/`pe_in_b_i`               | in  | 256     | The two operand words.                   |
| `sel_a_i`/`sel_b_i[0:7]`              | in  | 2 each  | Per-pair block selects → `disp_array`.   |
| `ctr_l_i`/`ctr_h_i[0:7]`              | in  | 2 each  | B-gate controls → `disp_array`.          |
| `is_signed_a_i`/`is_signed_b_i[0:15]` | in  | 1 each  | Per-DP8 signedness → `pe_array`.         |
| `sel_shift_i`                         | in  | 3       | Tree shift enables → `pe_array`.         |
| `acc_i[0:7]`                          | in  | 20 each | External accumulator word → `acc_array`. |
| `sel_out_i`                           | in  | 2       | Tap-level select → `acc_array`.          |
| `sel_acc_i`                           | in  | 1       | Accumulate select → `acc_array`.         |
| `prop_carry_i`                        | in  | 1       | Lane-fusion carry enable → `acc_array`.  |
| `pe_out_o[0:7]`                       | out | 20 each | Per-lane results.                        |

## Instantiation

```systemverilog
pe_datapath pe_datapath_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .pe_in_a_i(pe_in_a_i), .pe_in_b_i(pe_in_b_i),
    .sel_a_i(sel_a_ctrl), .sel_b_i(sel_b_ctrl),
    .ctr_l_i(ctr_l_ctrl), .ctr_h_i(ctr_h_ctrl),
    .is_signed_a_i(is_signed_a_ctrl), .is_signed_b_i(is_signed_b_ctrl),
    .sel_shift_i(sel_shift_dp),
    .acc_i(acc_q2), .sel_out_i(selout_q[0]),
    .sel_acc_i(selacc_q2[0]), .prop_carry_i(propc_q[0]),
    .pe_out_o(pe_out_o)
);
```

## Internal logic

Three instances, wired head to tail. `disp_array` routes the two 256-bit operands into the 16 `(a_dp8, b_dp8)` pairs; `pe_array` computes the 16 dot products and reduces them through its shift/compress tree, exposing the carry-save taps `l0`–`l3`; `acc_array` selects one tap level, resolves it, accumulates, and drives `pe_out_o`. The taps are the only internal signals:

```systemverilog
disp_array disp_array_i (..., .a_dp8_o(a_dp8), .b_dp8_o(b_dp8));
pe_array   pe_array_i   (.a_dp8_i(a_dp8), .b_dp8_i(b_dp8), ...,
                         .l0_sum_o(l0_sum), ..., .l3_carry_o(l3_carry));
acc_array  acc_array_i  (.l0_sum_i(l0_sum), ..., .l3_carry_i(l3_carry),
                         .acc_i(acc_i), ..., .pe_out_o(pe_out_o));
```

The three internal registers span two pipeline stages: the `disp_array` input register and the `pe_array` L0 register bracket the first stage (dispatch, DP8, L0 shift/compress), and the `acc_array` output register closes the second (L1/L2/L3 reduce, tap window, resolve, accumulate). This is why `top_pe_bas` delivers the first-stage controls one register earlier than the second-stage ones.

Source: [pe_datapath.sv](../../rtl/pe_datapath.sv)
