# Control

`ctrl` — the shared mode decoder and control pipeline of the PE grid. **One instance serves the whole grid**: the mode is grid-wide, so the decode is done once and broadcast to every PE rather than replicated per PE. It maps the 4-bit `mode_i` to every internal control the datapath needs, and it holds the control-path pipeline registers that used to live in the per-PE top level.

## Purpose

Each of the 11 operating modes reduces its large dot product to the `dp_8` primitive by a fixed recipe of block routing, operand signedness, tree shifts and tap level (see [modes](../../doc/diagrams/modes.excalidraw)). `ctrl` turns `mode_i` into that recipe: the [disp_array_a](./disp_array_a.md) A-block selects `sel_a`, the [disp_array_b](./disp_array_b.md) B-block selects `sel_b` and B-gate controls `ctr_l`/`ctr_h`, the [pe](./pe.md) per-DP8 signedness `is_signed_a`/`is_signed_b`, the tree shift enables `sel_shift`, the tap-level select `sel_out` and the lane-fusion carry enable `prop_carry`. It is a lookup table indexed by the mode bits — no sequencing, no handshake.

Because the datapath is a 3-stage pipeline whose controls are consumed at two different stages, `ctrl` also carries the control-path alignment that formerly lived in `top_pe_bas`: `mode_i` is registered once on input, the decode is combinational from the registered mode, and the second-stage controls (`sel_shift[2:1]`, `sel_out`, `prop_carry`) pass through one more register here so each control meets the data it belongs to. `sel_acc` is not decoded here — it is a runtime input the top level pipelines separately.

## Parameters

None — fixed to the PE configuration. The key `localparam`s: `NUM_PAIR = 8`, `NUM_DP8 = 16`, `SEL_WIDTH = 2`, `OP_WIDTH = 2`, `NUM_SHIFT = 3`, `SHIFT_HI = 2`, `MODE_WIDTH = 4`, `NUM_ENTRY = 16` (one LUT row per 4-bit mode value).

## Interface

| Signal                | Dir | Width  | Description                                                          |
| --------------------- | --- | ------ | -------------------------------------------------------------------- |
| `clk_i`               | in  | 1      | Clock.                                                               |
| `rst_ni`              | in  | 1      | Asynchronous active-low reset.                                       |
| `mode_i`              | in  | 4      | Operating-mode select (registered once on input).                    |
| `sel_a_o[0:7]`        | out | 2 each | Per-pair A block select → `disp_array_a`.                            |
| `sel_b_o[0:7]`        | out | 2 each | Per-pair B block select → `disp_array_b`.                            |
| `ctr_l_o[0:7]`        | out | 2 each | B-gate (pass / zero / negate) for the L half.                        |
| `ctr_h_o[0:7]`        | out | 2 each | B-gate for the H half.                                               |
| `is_signed_a_o[0:15]` | out | 1 each | Per-DP8 A signedness → `pe`.                                         |
| `is_signed_b_o[0:15]` | out | 1 each | Per-DP8 B signedness → `pe`.                                         |
| `sel_shift_o`         | out | 3      | Tree shift enables — bit 0 combinational, bits 2:1 registered.       |
| `sel_out_o`           | out | 2      | Tap-level select (registered) → `pe`.                                |
| `en_level_o`          | out | 3      | Tree operand-isolation enables (registered), decoded from `sel_out`. |
| `prop_carry_o`        | out | 1      | Lane-fusion carry enable (registered) → `pe`.                        |

## Instantiation

```systemverilog
ctrl ctrl_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .mode_i(mode_i),
    .sel_a_o(sel_a), .sel_b_o(sel_b),
    .ctr_l_o(ctr_l), .ctr_h_o(ctr_h),
    .is_signed_a_o(is_signed_a), .is_signed_b_o(is_signed_b),
    .sel_shift_o(sel_shift),
    .sel_out_o(sel_out), .prop_carry_o(prop_carry),
    .en_level_o(en_level)
);
```

## Internal logic

### The input register

`mode_i` is registered once by a [reg_n](./reg_n.md) into `mode_q1`; the whole decode below reads the registered mode. Registering the 4-bit `mode` rather than the ~100-bit decoded bundle is the cheaper split, and it puts the first-stage decode outputs in the same cycle the [disp_array_a](./disp_array_a.md) / [disp_array_b](./disp_array_b.md) mux/gate and the `pe_array` DP8 / L0 shift consume them.

```systemverilog
reg_n #(.WIDTH(MODE_WIDTH), .SIZE(1)) reg_mode_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(mode_d), .q_o(mode_q1)
);
```

### The lookup table

Each control is a `localparam` constant array with one row per mode value, sized `[0:15]` and indexed directly by the registered mode. The 11 valid modes (1-3, 5-12) hold their recipe; the unused indices (0, 4, 13-15) default to zero, a harmless no-shift / pass-through. A per-pair / per-DP8 `generate` reads the selected row combinationally:

```systemverilog
assign sel_a_o[p] = SEL_A_LUT[mode_q1[0]][p];
assign is_signed_a_o[i] = IS_SIGNED_A_LUT[mode_q1[0]][i];
```

The row values are the authoritative per-mode decode — the same Dispatch / Shifter vectors the `disp_array_a`/`disp_array_b` and `pe_array` testbenches drive by hand, here owned once by the decoder. The scalar controls per mode:

| Mode | `sel_out` (tap) | `prop_carry` | `sel_shift` |
| ---- | --------------- | ------------ | ----------- |
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
assign prop_carry_c = (SEL_OUT_LUT[mode_q1[0]] != '0);
```

### The stage-2 output registers

The disp selects/gates, the per-DP8 signedness and the L0 shift (`sel_shift[0]`) act in the first datapath stage and go straight out combinationally. The L1/L2 shifts (`sel_shift[2:1]`), `sel_out` and `prop_carry` act one stage later (after the `pe_array` L0 register), so each passes through one more register here — the alignment that used to live in the dissolved per-PE top level:

```systemverilog
reg_n #(.WIDTH(SHIFT_HI),  .SIZE(1)) reg_shifthi_i (...);  // sel_shift[2:1]
reg_n #(.WIDTH(SEL_WIDTH), .SIZE(1)) reg_selout_i  (...);  // sel_out
reg_n #(.WIDTH(1),         .SIZE(1)) reg_propc_i   (...);  // prop_carry
```

`sel_shift` is a single 3-bit bus, but its bits are used one stage apart: bit 0 shifts L0 (stage 1), bits 2:1 shift L1/L2 (stage 2). So the bus is reassembled with its low bit combinational and its high bits registered:

```systemverilog
assign sel_shift_o = {shifthi_q[0], sel_shift_c[0]};
assign en_level_o  = {&selout_q[0], selout_q[0][1], |selout_q[0]};
```

Source: [ctrl.sv](../../rtl/ctrl.sv)
