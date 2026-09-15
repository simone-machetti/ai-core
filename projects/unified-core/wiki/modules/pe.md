# Processing Element

`pe` — the self-contained per-PE core of the grid. It takes the already-dispatched operands (`a_dp8`/`b_dp8` from [disp_array_a](./disp_array_a.md)/[disp_array_b](./disp_array_b.md), shared across its row/column) and the broadcast control from [ctrl](./ctrl.md), and chains **operand isolation → [pe_array](./pe_array.md) → [acc_array](./acc_array.md)** plus the two `acc` pipeline registers. It is instantiated N² times by the grid, one per cell; the shared control and dispatch that used to be replicated per PE now sit above it.

## Purpose

`pe` is what remains of a Processing Element once the grid-wide control decode and the per-row/per-column operand dispatch are hoisted out: the multiplier array, the accumulator, the `en_i` operand mask, and the `acc` pipeline that meets the tap at the accumulate stage. The old `top_pe_bas` top level and `pe_datapath` wrapper are dissolved into this module and the [top_NxN](../architectures/top_NxN.md) grid; the single-PE test is now `top_NxN` at `N = 1`.

The PE is fed by the shared dispatch (broadcast to the whole row/column) and computes one of the 11 modes selected grid-wide. `en_i` is the PE's active-high enable: it AND-masks both dispatched operands so a clock-gated PE stays glitch-free (see below). `sel_out`, `sel_acc` and `prop_carry` arrive **already pipelined** — `sel_acc` once (shared, in the grid), `sel_out`/`prop_carry` in `ctrl` — so this module adds no control-alignment logic of its own; only `acc_i` is pipelined here.

## Parameters

None — fixed to the PE configuration; the shape is baked in as `localparam`s. The key ones:

| Localparam                    | Value             | Meaning                             |
| ----------------------------- | ----------------- | ----------------------------------- |
| `NUM_DP8`                     | 16                | DP8 cores driving the tree.         |
| `A_DP8_WIDTH`/`B_DP8_WIDTH`   | 64 / 32           | Dispatched A / B operand per DP8.   |
| `NUM_LANE`                    | 8                 | Output lanes.                       |
| `PE_WIDTH`                    | 20                | Per-lane / `acc_i` / `out_o` width. |
| `NUM_SHIFT`                   | 3                 | Tree shift-enable bits.             |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | 18 / 29 / 37 / 38 | `pe_array` tap widths.              |

## Interface

| Signal                | Dir | Width   | Description                                                                       |
| --------------------- | --- | ------- | --------------------------------------------------------------------------------- |
| `clk_i`               | in  | 1       | Clock (gated per PE by that PE's ICG).                                            |
| `rst_ni`              | in  | 1       | Asynchronous active-low reset (ungated).                                          |
| `a_dp8_i[0:15]`       | in  | 64 each | Dispatched A per DP8, from the row's `disp_array_a`.                              |
| `b_dp8_i[0:15]`       | in  | 32 each | Dispatched B per DP8, from the column's `disp_array_b`.                           |
| `en_i`                | in  | 1       | Active-high PE enable — AND-masks both operands; also gates the clock externally. |
| `is_signed_a_i[0:15]` | in  | 1 each  | Per-DP8 A signedness, from `ctrl`.                                                |
| `is_signed_b_i[0:15]` | in  | 1 each  | Per-DP8 B signedness, from `ctrl`.                                                |
| `sel_shift_i`         | in  | 3       | Tree shift enables, from `ctrl`.                                                  |
| `en_level_i`          | in  | 3       | Tree operand-isolation enables, from `ctrl` — masks levels below the tap.         |
| `acc_i[0:7]`          | in  | 20 each | External accumulator word (per PE) — pipelined here.                              |
| `sel_out_i`           | in  | 2       | Tap-level select (already registered in `ctrl`).                                  |
| `sel_acc_i`           | in  | 1       | Accumulate select (already pipelined in the grid).                                |
| `prop_carry_i`        | in  | 1       | Lane-fusion carry enable (already registered in `ctrl`).                          |
| `out_o[0:7]`          | out | 20 each | Per-lane results; a fused result is `{out[even], out[odd]}`.                      |

## Instantiation

```systemverilog
pe pe_i (
    .clk_i(clk_pe), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8_row[r]), .b_dp8_i(b_dp8_col[c]),
    .en_i(en_pe),
    .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
    .sel_shift_i(sel_shift), .en_level_i(en_level),
    .acc_i(acc_i[r][c]),
    .sel_out_i(sel_out), .sel_acc_i(selacc_q2[0]), .prop_carry_i(prop_carry),
    .out_o(out_q_o[r][c])
);
```

## Internal logic

Two instances wired head to tail — `pe_array` then `acc_array` — bracketed by the operand mask on the input and the `acc` pipeline into the accumulate stage. The datapath is a 3-stage pipeline: the `disp_array_*` operand input register (above this module), the `pe_array` L0 register, and the `acc_array` output register.

### Operand isolation (the en_i mask)

`en_i` AND-masks both dispatched operands to zero before they reach `pe_array`:

```systemverilog
for (d = 0; d < NUM_DP8; d++) begin : gen_mask
    assign a_dp8_m[d] = a_dp8_i[d] & {A_DP8_WIDTH{en_i}};
    assign b_dp8_m[d] = b_dp8_i[d] & {B_DP8_WIDTH{en_i}};
end
```

The PE's clock is gated externally by the same enable (one [icg](./icg.md) per PE), which freezes `pe_array`/`acc_array`. But the `pe_array` multipliers sit *before* the first PE register (the `pe_array` L0 register) and are fed by the still-toggling **shared** dispatch — so without the mask they would keep switching while the PE is gated, burning power. Masking A alone already zeros every partial product; both are masked for a fully-quiet DP8.

### The acc pipeline

`acc_i` is the per-PE external accumulator word. It is delayed by two [reg_n](./reg_n.md) registers so it meets its tap at the accumulate stage, in the same issue time-base as the operands:

```systemverilog
reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc1_i (.d_i(acc_i),  .q_o(acc_q1), ...);
reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc2_i (.d_i(acc_q1), .q_o(acc_q2), ...);
```

### pe_array → acc_array

`pe_array` takes the masked operands and the per-DP8 signedness / shift controls, computes the 16 dot products, and reduces them through its shift/compress tree, exposing the carry-save taps `l0`–`l3`. `acc_array` selects the tap level `sel_out_i`, resolves it, folds in `acc_q2` or its own register feedback (`sel_acc_i`), chains the lane-fusion carry (`prop_carry_i`), and drives `out_o`:

```systemverilog
pe_array  pe_array_i  (.a_dp8_i(a_dp8_m), .b_dp8_i(b_dp8_m), ..., .l0_sum_o(l0_sum), ..., .l3_carry_o(l3_carry));
acc_array acc_array_i (.l0_sum_i(l0_sum), ..., .l3_carry_i(l3_carry),
                       .acc_i(acc_q2), .sel_out_i(sel_out_i), .sel_acc_i(sel_acc_i),
                       .prop_carry_i(prop_carry_i), .pe_out_o(out_o));
```

`out_o` is valid 3 clocks after the operands and mode are applied. `sel_acc = 0` folds `acc_i` (a fresh result, or an external bias/running sum), `sel_acc = 1` folds the lane's own register back in (accumulate over cycles).

Source: [pe.sv](../../rtl/pe.sv) — Testbench: [tb_top_NxN.sv](../../tb/tb_top_NxN.sv) (via the grid) — Diagram: [pe](../../doc/diagrams/pe.excalidraw)
