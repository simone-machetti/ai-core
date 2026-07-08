# PE Control

`pe_ctrl` — the combinational mode decoder of the PE. It maps the 4-bit `mode_i` to every internal control the datapath needs and holds no state; all pipeline alignment lives in [top_pe_bas](../architectures/top_pe_bas.md).

## Purpose

Each of the 11 operating modes reduces its large dot product to the `dp_8` primitive by a fixed recipe of block routing, operand signedness, tree shifts and tap level (see [modes](../../doc/diagrams/modes.md)). `pe_ctrl` turns `mode_i` into that recipe: the [disp_array](./disp_array.md) block selects `sel_a`/`sel_b` and B-gate controls `ctr_l`/`ctr_h`, the [pe_array](./pe_array.md) per-DP8 signedness `is_signed_a`/`is_signed_b` and shift enables `sel_shift`, and the [acc_array](./acc_array.md) tap-level select `sel_out` and lane-fusion carry enable `prop_carry`. It is a lookup table indexed by the mode bits — no sequencing, no handshake. `sel_acc` is not decoded here: it is a runtime input pipelined alongside `mode` in `top_pe_bas`.

## Parameters

None — fixed to the PE configuration. The key `localparam`s: `NUM_PAIR = 8`, `NUM_DP8 = 16`, `MODE_WIDTH = 4`, `NUM_ENTRY = 16` (one LUT row per 4-bit mode value).

## Interface

| Signal                | Dir | Width  | Description                                   |
| --------------------- | --- | ------ | --------------------------------------------- |
| `mode_i`              | in  | 4      | Operating-mode select.                        |
| `sel_a_o[0:7]`        | out | 2 each | Per-pair A block select → `disp_array`.       |
| `sel_b_o[0:7]`        | out | 2 each | Per-pair B block select → `disp_array`.       |
| `ctr_l_o[0:7]`        | out | 2 each | B-gate (pass / zero / negate) for the L half. |
| `ctr_h_o[0:7]`        | out | 2 each | B-gate for the H half.                        |
| `is_signed_a_o[0:15]` | out | 1 each | Per-DP8 A signedness → `pe_array`.            |
| `is_signed_b_o[0:15]` | out | 1 each | Per-DP8 B signedness → `pe_array`.            |
| `sel_shift_o`         | out | 3      | Tree shift-stage enables (L0 / L1 / L2).      |
| `sel_out_o`           | out | 2      | Tap-level select → `acc_array`.               |
| `prop_carry_o`        | out | 1      | Lane-fusion carry enable → `acc_array`.       |

## Instantiation

```systemverilog
pe_ctrl pe_ctrl_i (
    .mode_i(mode_q1[0]),
    .sel_a_o(sel_a_ctrl), .sel_b_o(sel_b_ctrl),
    .ctr_l_o(ctr_l_ctrl), .ctr_h_o(ctr_h_ctrl),
    .is_signed_a_o(is_signed_a_ctrl), .is_signed_b_o(is_signed_b_ctrl),
    .sel_shift_o(sel_shift_ctrl),
    .sel_out_o(sel_out_ctrl), .prop_carry_o(prop_carry_ctrl)
);
```

## Internal logic

### The lookup table

Each control is a `localparam` constant array with one row per mode value, sized `[0:15]` and indexed directly by `mode_i`. The 11 valid modes (1-3, 5-12) hold their recipe; the unused indices (0, 4, 13-15) default to zero, a harmless no-shift / pass-through. A per-pair / per-DP8 `generate` reads the selected row combinationally:

```systemverilog
assign sel_a_o[p] = SEL_A_LUT[mode_i][p];
assign is_signed_a_o[i] = IS_SIGNED_A_LUT[mode_i][i];
```

The row values are the authoritative per-mode decode — the same Dispatch / Shifter vectors the `disp_array` and `pe_array` testbenches drive by hand, here owned once by the decoder. The scalar controls per mode:

| Mode | `sel_out` (tap) | `prop_carry` | `sel_shift` |
| ---: | --------------- | ------------ | ----------- |
| 1    | 0 (L0)          | 0            | `000`       |
| 2    | 1 (L1)          | 1            | `010`       |
| 3    | 1 (L1)          | 1            | `011`       |
| 5    | 2 (L2)          | 1            | `000`       |
| 6    | 3 (L3)          | 1            | `010`       |
| 7    | 2 (L2)          | 1            | `011`       |
| 8    | 3 (L3)          | 1            | `111`       |
| 9    | 2 (L2)          | 1            | `111`       |
| 10   | 1 (L1)          | 1            | `010`       |
| 11   | 2 (L2)          | 1            | `010`       |
| 12   | 2 (L2)          | 1            | `111`       |

### Deriving prop_carry

`prop_carry` fuses a lane pair whenever a result is wider than one lane, which is exactly when the tap level is above L0. Rather than a parallel table it is derived from `sel_out`, so the two can never drift:

```systemverilog
assign prop_carry_o = (SEL_OUT_LUT[mode_i] != '0);
```

Source: [pe_ctrl.sv](../../rtl/pe_ctrl.sv)
