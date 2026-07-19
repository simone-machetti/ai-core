# Control (Square)

`ctrl_sqr` — the shared mode decoder and control pipeline for the **square** grid, the [ctrl](./ctrl.md) analogue. One instance serves the whole [top_NxN_sqr](../architectures/top_NxN_sqr.md): the mode is grid-wide, decoded once and broadcast to every PE, dispatcher and α/β generator.

## Purpose

`ctrl_sqr` maps the 4-bit `mode_i` to every square control. Compared with `ctrl` it **drops** `ctr_l`/`ctr_h` (the square B dispatcher has no shift) and **adds** three:

- **`zero`** — per-DP8 idle-zero (modes 5/6), for the dispatchers and the β generator.
- **`neg`** — the 6-bit `comp_n` block-negate (modes 10/11), for `pe_array_sqr` and the α/β generators.
- **`sel_const`** — the [acc_array_sqr](./acc_array_sqr.md) const-mux pattern (`0`=L0, `1`=`c_o` both halves, `2`=complex L1 mode 10, `3`=complex L2 mode 11).

Plus the shared ones: `sel_a`, `sel_b` (dispatch routing), `is_signed_a`/`is_signed_b` (centering + generator removed-operand bias; **mode 5 is all-signed** here for idle-clean, unlike the multiply `ctrl`), `sel_shift`, `sel_out`, `prop_carry`.

**Pipeline** (identical scheme to `ctrl`): `mode_i` is registered once (`mode_q1`), the decode is combinational from it; the first-stage controls (dispatch, signed, idle-zero, block-negate, `sel_shift[0]`) go straight out, and the second-stage controls (`sel_shift[2:1]`, `sel_out`, `sel_const`, `prop_carry`) pass through one more register so each meets the data it belongs to. `sel_acc` and the constant ([const_sqr](./const_sqr.md)) are handled at the top level.

## Parameters

None — fixed to the PE configuration. Key `localparam`s: `NUM_PAIR = 8`, `NUM_DP8 = 16`, `SEL_WIDTH = 2`, `NUM_SHIFT = 3`, `NUM_NEG = 6`, `SHIFT_HI = 2`, `MODE_WIDTH = 4`, `NUM_ENTRY = 16` (one LUT row per 4-bit mode).

## Interface

| Signal                          | Dir | Width | Description                                    |
| ------------------------------- | --- | ----- | ---------------------------------------------- |
| `clk_i` / `rst_ni`              | in  | 1     | Clock / async reset.                           |
| `mode_i`                        | in  | 4     | Grid-wide mode.                                |
| `sel_a_o`/`sel_b_o`             | out | 2×8   | A / B block selects (dispatch routing).        |
| `is_signed_a_o`/`is_signed_b_o` | out | 1×16  | Per-DP8 centering / generator-bias signedness. |
| `zero_o`                        | out | 1×16  | Per-DP8 idle-zero.                             |
| `neg_o`                         | out | 6     | Complex block-negate.                          |
| `sel_shift_o`                   | out | 3     | Tree shift enables.                            |
| `sel_out_o`                     | out | 2     | Tap-level select.                              |
| `sel_const_o`                   | out | 2     | Const-mux pattern.                             |
| `prop_carry_o`                  | out | 1     | Lane-fusion carry enable.                      |

Source: [ctrl_sqr.sv](../../rtl/ctrl_sqr.sv)
