# Accumulator Array (Bit-Plane BFP)

`acc_array_bpl_bfp` — the accumulator of the bit-plane variant. Structurally and behaviourally identical to [acc_array_bfp](./acc_array_bfp.md); **only the input tap widths differ**, resized for [pe_array_bpl_a_bfp](./pe_array_bpl_a_bfp.md)'s tree.

## Purpose

The bit-plane tree carries its nodes at different widths than the Booth tree, so its taps arrive wider. Nothing else about the accumulate loop changes: it still resolves the selected tap, accumulates it, fuses lane pairs into the wide results, and keeps the BFP alignment inside the loop with a running-max exponent.

This module exists only so the port widths match. Every internal mechanism is documented on [acc_array_bfp](./acc_array_bfp.md).

## Parameters

None — fixed to the PE configuration. The only deltas against [acc_array_bfp](./acc_array_bfp.md):

| Localparam | `acc_array_bfp` | `acc_array_bpl_bfp` | Meaning                   |
| ---------- | --------------- | ------------------- | ------------------------- |
| `L0_WIDTH` | 18              | 18                  | L0 tap width (unchanged). |
| `L1_WIDTH` | 29              | **36**              | L1 tap width.             |
| `L2_WIDTH` | 37              | **40** (`FUSE`)     | L2 tap width.             |
| `L3_WIDTH` | 38              | **40** (`FUSE`)     | L3 tap width.             |

`PE_WIDTH = 20`, `FUSE = 40`, `EXP_WIDTH = 7`, `NUM_LANE = 8` are all as the baseline-BFP.

## Interface

Port-for-port [acc_array_bfp](./acc_array_bfp.md), with `l1_*_i` at 36 bits and `l2_*_i` / `l3_*_i` at 40:

| Signal                            | Dir | Width       | Description                           |
| --------------------------------- | --- | ----------- | ------------------------------------- |
| `clk_i` / `rst_ni`                | in  | 1           | Clock, asynchronous active-low reset. |
| `l0_sum_i` / `l0_carry_i[0:7]`    | in  | 18 each     | L0 taps (carry-save).                 |
| `l1_sum_i` / `l1_carry_i[0:3]`    | in  | **36** each | L1 taps.                              |
| `l2_sum_i` / `l2_carry_i[0:1]`    | in  | **40** each | L2 taps.                              |
| `l3_sum_i` / `l3_carry_i`         | in  | **40**      | L3 tap.                               |
| `l0_exp_i` … `l3_exp_i`           | in  | 7 each      | Per-tap scales.                       |
| `acc_i[0:7]` / `acc_exp_i[0:7]`   | in  | 20 / 7      | Accumulator seed mantissa and scale.  |
| `sel_out_i`                       | in  | 2           | Which level to read.                  |
| `sel_acc_i`                       | in  | 1           | Seed vs feedback.                     |
| `prop_carry_i`                    | in  | 1           | Lane-pair fusion carry propagate.     |
| `pe_out_o[0:7]` / `pe_exp_o[0:7]` | out | 20 / 7      | Per-lane result mantissa and scale.   |

## Instantiation

```systemverilog
acc_array_bpl_bfp acc_array_bpl_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .l0_sum_i(l0_sum), .l0_carry_i(l0_carry), .l0_exp_i(l0_exp),
    .l1_sum_i(l1_sum), .l1_carry_i(l1_carry), .l1_exp_i(l1_exp),
    .l2_sum_i(l2_sum), .l2_carry_i(l2_carry), .l2_exp_i(l2_exp),
    .l3_sum_i(l3_sum), .l3_carry_i(l3_carry), .l3_exp_i(l3_exp),
    .acc_i(acc_q2), .acc_exp_i(acc_exp_q2),
    .sel_out_i(sel_out), .sel_acc_i(sel_acc), .prop_carry_i(prop_carry),
    .pe_out_o(out), .pe_exp_o(out_exp)
);
```

## Internal logic

Unchanged from [acc_array_bfp](./acc_array_bfp.md). The reason no other change is needed is that the module **already sign-extended every tap to `FUSE` before splitting it into lanes**:

```systemverilog
assign l1s = FUSE'($signed(l1_sum_i[g/2]));
assign l1c = FUSE'($signed(l1_carry_i[g/2]));
```

A wider incoming tap simply extends less. The `L2_WIDTH = L3_WIDTH = FUSE` case degenerates to no extension at all — the tap arrives already at the fused width. Lane splitting (`H` = `[FUSE-1:PE_WIDTH]` for even lanes, `L` = `[PE_WIDTH-1:0]` for odd), the tap mux, the acc mux, the in-loop [align_cell_bfp](./align_cell_bfp.md), the running-max exponent register and the fusion carry chain are all byte-for-byte the baseline-BFP's.

Measured cost of the wider inputs: `884.83` vs `861.04` µm² inside the PE, **+2.8 %** — see [Intra-PE Area](../experiments/syn_pe_area.md).

## Verification

[tb_acc_array_bpl_a_bfp](../testbenches/tb_acc_array_bpl_a_bfp.md) runs the whole bit-plane datapath (dispatchers → [pe_array_bpl_a_bfp](./pe_array_bpl_a_bfp.md) → this) against the integer path and a matmul golden: Pass A equal-exponent agreement at `pe_out` across single-shot and accumulation, Pass B the min-scale-seed closed form. All 11 modes, all 8 lanes, 0 mismatches.

Source: [acc_array_bpl_bfp.sv](../../rtl/acc_array_bpl_bfp.sv) — Testbench: [tb_acc_array_bpl_a_bfp.sv](../../tb/tb_acc_array_bpl_a_bfp.sv)
