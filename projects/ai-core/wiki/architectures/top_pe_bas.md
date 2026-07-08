# Processing Element (baseline)

`top_pe_bas` — the baseline top level of one Processing Element: a reconfigurable fixed-point MatMul engine built from 16 [dp_8](../modules/dp_8.md) cores that evaluates one of the 11 operating modes selected by `mode_i`. It is the reference architecture that later variants are compared against. It wires the combinational mode decoder [pe_ctrl](../modules/pe_ctrl.md) to the [pe_datapath](../modules/pe_datapath.md) (`disp_array → pe_array → acc_array`) and adds the control-path pipeline registers that align each decoded control with the data it meets.

## Purpose

The caller drives the two 256-bit operands, `mode_i`, `sel_acc_i` and `acc_i`, and reads `pe_out_o` three clocks later. Everything the datapath needs internally — the dispatch block selects and B-gates, the per-DP8 signedness and tree shifts, the tap-level select and lane-fusion carry — is derived from `mode_i` by `pe_ctrl`; `top_pe_bas` only decodes the mode once and delays each control by the right number of registers so it lands on the correct pipeline stage. `sel_acc_i` and `acc_i` are not mode-derived — they arrive at the top alongside `mode_i` and are pipelined the same way.

## Parameters

None — fixed to the PE configuration; the shape is baked in as `localparam`s. The key ones:

| Localparam    | Value | Meaning                                                 |
| ------------- | ----- | ------------------------------------------------------- |
| `PE_IN_WIDTH` | 256   | Operand width (`NUM_BLK · BLK_WIDTH`, 4 × 64).          |
| `MODE_WIDTH`  | 4     | Mode select width (11 valid modes: 1-3, 5-12).          |
| `NUM_LANE`    | 8     | Output lanes.                                           |
| `PE_WIDTH`    | 20    | Per-lane / `acc_i` / `pe_out` width.                    |
| `NUM_SHIFT`   | 3     | Tree shift-enable bits.                                 |
| `SHIFT_HI`    | 2     | Shift bits used in the second stage (`sel_shift[2:1]`). |

## Interface

| Signal          | Dir | Width   | Description                                                              |
| --------------- | --- | ------- | ------------------------------------------------------------------------ |
| `clk_i`         | in  | 1       | Clock.                                                                   |
| `rst_ni`        | in  | 1       | Asynchronous active-low reset.                                           |
| `pe_in_a_i`     | in  | 256     | Operand A — 4 × 64-bit blocks, each block 8 × int8.                      |
| `pe_in_b_i`     | in  | 256     | Operand B — 4 × 64-bit blocks, each two 32-bit halves of 8 × int4.       |
| `mode_i`        | in  | 4       | Operating-mode select (decoded by `pe_ctrl`).                            |
| `sel_acc_i`     | in  | 1       | Fresh output (`0`, folds `acc_i`) vs accumulate onto the register (`1`). |
| `acc_i[0:7]`    | in  | 20 each | External accumulator word, one per lane.                                 |
| `pe_out_o[0:7]` | out | 20 each | Per-lane results; a fused result is `{pe_out[even], pe_out[odd]}`.       |

## Instantiation

```systemverilog
top_pe_bas top_pe_bas_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .pe_in_a_i(pe_in_a), .pe_in_b_i(pe_in_b),
    .mode_i(mode), .sel_acc_i(sel_acc), .acc_i(acc_word),
    .pe_out_o(pe_out)
);
```

## Internal logic

The datapath is a 3-stage pipeline, with all three registers inside [pe_datapath](../modules/pe_datapath.md): the `disp_array` input register, the `pe_array` L0 register, and the `acc_array` output register. `pe_ctrl` is purely combinational, so every control-path register lives here in `top_pe_bas`. The controls are consumed at two different stages, so each is delayed to match:

| Control                                                          | Consumed | Registers from input | Source in `top_pe_bas`         |
| ---------------------------------------------------------------- | -------- | -------------------- | ------------------------------ |
| `sel_a`/`sel_b`/`ctr_l`/`ctr_h`, `is_signed_a/b`, `sel_shift[0]` | stage 1  | 1                    | input reg (`mode`) → `pe_ctrl` |
| `sel_shift[2:1]`, `sel_out`, `prop_carry`                        | stage 2  | 2                    | `pe_ctrl` → group-2 reg        |
| `sel_acc`, `acc`                                                 | stage 2  | 2                    | input reg → group-3 reg        |

All registers reuse [reg_n](../modules/reg_n.md).

### Input register and decode

`mode_i`, `sel_acc_i` and `acc_i` are registered once on input, then `pe_ctrl` decodes the registered `mode` — registering the 4-bit `mode` rather than the ~100-bit decoded bundle is the cheaper split. The decode output lands in the first datapath stage (the `disp_array` mux/gate and the `pe_array` DP8 / L0 shift all consume it there), so the disp controls, the per-DP8 signedness and `sel_shift[0]` need no further delay:

```systemverilog
reg_n #(.WIDTH(MODE_WIDTH), .SIZE(1)) reg_mode_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(mode_d), .q_o(mode_q1)
);
pe_ctrl pe_ctrl_i (.mode_i(mode_q1[0]), ...);
```

### The second-stage registers

The `pe_array` L1/L2 shifts and every `acc_array` control are consumed one stage later (after the L0 register), so they take one more register. The group-2 register delays the decoded `sel_shift[2:1]`, `sel_out` and `prop_carry`; the group-3 register delays `sel_acc` and `acc` (which were already registered once on input, giving them the same 2-cycle depth):

```systemverilog
reg_n #(.WIDTH(SHIFT_HI),  .SIZE(1))        reg_shifthi_i (...);
reg_n #(.WIDTH(SEL_WIDTH), .SIZE(1))        reg_selout_i  (...);
reg_n #(.WIDTH(1),         .SIZE(1))        reg_propc_i   (...);
reg_n #(.WIDTH(1),         .SIZE(1))        reg_selacc2_i (.d_i(selacc_q1), ...);
reg_n #(.WIDTH(PE_WIDTH),  .SIZE(NUM_LANE)) reg_acc2_i    (.d_i(acc_q1),    ...);
```

### Reassembling sel_shift

`sel_shift` is a single 3-bit bus into `pe_array`, but its bits are used one stage apart: bit 0 shifts L0 (stage 1), bits 2:1 shift L1/L2 (stage 2). So the bus handed to the datapath takes bit 0 straight from the decode and bits 2:1 from the group-2 register:

```systemverilog
assign sel_shift_dp = {shifthi_q[0], sel_shift_ctrl[0]};
```

### Latency and accumulation

`pe_out_o` is valid 3 clocks after the operands and mode are applied. Because `sel_acc`, `acc` and the operands all traverse 3 registers to `pe_out`, an operation issued in one cycle sees its own controls at the accumulator stage. `sel_acc = 0` folds `acc_i` (a fresh result, or an external bias/running sum), `sel_acc = 1` folds the lane's own register back in (accumulate over cycles).

Verified end to end across all 11 modes, single-shot and accumulating, with [tb_top_pe_bas](../testbenches/tb_top_pe_bas.md).

Source: [top_pe_bas.sv](../../rtl/top_pe_bas.sv) — Diagram: [top_pe_bas](../../doc/diagrams/top_pe_bas.excalidraw)
