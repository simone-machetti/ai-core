# PE Grid (baseline)

`top_NxN` — the baseline **N × N grid** of Processing Elements: it tiles N² [pe](../modules/pe.md) cores into a square array, sharing operand A along each row and operand B along each column, so PE[r][c] evaluates `A[r] · B[c]`. `N` is a parameter — **default 2** for a fast build; the full chip uses `N = 8`. This is the only baseline top level: the single-PE case is simply `top_NxN` at **N = 1** (the old `top_pe_bas` is dissolved into this grid).

## Purpose

An outer-product tiling: with A broadcast per row and B per column, the N² PEs cover every `A[row] · B[col]` pairing in parallel, each an independent matmul in one of the 11 modes. The redundant per-PE control and operand dispatch are **hoisted and shared** across the grid — the mode is grid-wide, so one [ctrl](../modules/ctrl.md) decodes it for every PE; the A path is registered/dispatched once per row by a [disp_array_a](../modules/disp_array_a.md), the B path once per column by a [disp_array_b](../modules/disp_array_b.md). `sel_acc` is a grid-wide runtime control, pipelined once here. The external accumulator word `acc` and the registered output `out_q` stay per PE.

Clock gating is **row/column-based** for matrix scaling: enables `en_row_i[N]` and `en_col_i[N]` (active-high) replace the old per-PE `clk_gate`. A PE runs when its row **and** column are enabled (`en_row[r] & en_col[c]`), so the active region is any `enabled_rows × enabled_cols` rectangle — the grid scales down from N × N. The module is purely structural: shared control/dispatch, fan-out wiring, the ICG cells, and N² PEs.

## Parameters

| Parameter | Default | Meaning                                               |
| --------- | ------- | ----------------------------------------------------- |
| `N`       | 2       | Grid side — the array is `N × N` PEs (chip: `N = 8`). |

Derived `localparam`s: `NUM_ROW = NUM_COL = N`, `PE_IN_WIDTH = 256`, `MODE_WIDTH = 4`, `NUM_LANE = 8`, `PE_WIDTH = 20`.

## Interface

| Signal                       | Dir | Width    | Description                                         |
| ---------------------------- | --- | -------- | --------------------------------------------------- |
| `clk_i`, `rst_ni`            | in  | 1        | Clock and asynchronous active-low reset (ungated).  |
| `in_a_i[0:N-1]`              | in  | 256 each | Operand A, one per row (shared across the row).     |
| `in_b_i[0:N-1]`              | in  | 256 each | Operand B, one per column (shared down the column). |
| `mode_i`                     | in  | 4        | Operating mode, broadcast to all PEs.               |
| `sel_acc_i`                  | in  | 1        | Accumulate select, broadcast to all PEs.            |
| `acc_i[0:N-1][0:N-1][0:7]`   | in  | 20 each  | External accumulator word, per PE (8 lanes).        |
| `en_row_i[0:N-1]`            | in  | 1 each   | Active-high row enable — `1` runs the row.          |
| `en_col_i[0:N-1]`            | in  | 1 each   | Active-high column enable — `1` runs the column.    |
| `out_q_o[0:N-1][0:N-1][0:7]` | out | 20 each  | Per-PE registered result (8 lanes).                 |

## Instantiation

```systemverilog
top_NxN #(.N(8)) grid_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .in_a_i(in_a), .in_b_i(in_b),
    .mode_i(mode), .sel_acc_i(sel_acc),
    .acc_i(acc),
    .en_row_i(en_row), .en_col_i(en_col),
    .out_q_o(out_q)
);
```

## Internal logic

The grid is built from one shared decode, per-row/per-column dispatch, and the N² PE array:

- **Shared control** — one `ctrl` decodes `mode_i` into every datapath control (`sel_a`/`sel_b`/`ctr_l`/`ctr_h`, per-DP8 signedness, `sel_shift`, `sel_out`, `prop_carry`) and holds the stage-2 control-pipeline registers. It runs **ungated**.
- **Shared sel_acc pipeline** — two `reg_n` stages delay `sel_acc_i` so it meets the accumulate stage in the same issue time-base as the operands. Also **ungated**.
- **Per-row A dispatch** — one `disp_array_a` per row registers `in_a_i[r]` and broadcasts the dispatched A to that row's PEs.
- **Per-column B dispatch** — one `disp_array_b` per column registers `in_b_i[c]`, applies the B gating, and broadcasts the dispatched B to that column's PEs.
- **PE array** — N² `pe` cores; PE[r][c] consumes `a_dp8_row[r]` and `b_dp8_col[c]`.

```systemverilog
assign en_pe = en_row_i[r] & en_col_i[c];
icg icg_pe_i (.clk_i(clk_i), .en_i(en_pe), .clk_o(clk_pe));
pe  pe_i     (.clk_i(clk_pe), .rst_ni(rst_ni),
              .a_dp8_i(a_dp8_row[r]), .b_dp8_i(b_dp8_col[c]), .en_i(en_pe),
              .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
              .sel_shift_i(sel_shift), .acc_i(acc_i[r][c]),
              .sel_out_i(sel_out), .sel_acc_i(selacc_q2[0]), .prop_carry_i(prop_carry),
              .out_o(out_q_o[r][c]) );
```

- **Fan-out:** `in_a_i[r]` reaches every PE in row `r` (through the row's `disp_array_a`); `in_b_i[c]` every PE in column `c` (through the column's `disp_array_b`).
- **Clock gating & scaling:** a PE's [icg](../modules/icg.md) enable is `en_row[r] & en_col[c]`; the same `en_pe` also AND-masks that PE's operands (a disabled PE stops toggling and holds its registers). Each row's `disp_array_a` and each column's `disp_array_b` get their own ICG (`en_row[r]` / `en_col[c]`) so a fully-disabled row or column freezes its dispatch too. `rst_ni` is not gated, so a frozen PE still resets. Enabling an `nr × nc` rectangle runs exactly those PEs and holds the rest at their reset value — this is how the grid scales down from N × N.
- **ICG count:** N² (one per PE) + N (one per `disp_array_a`) + N (one per `disp_array_b`). `ctrl` and the `sel_acc` pipeline are ungated.
- **Latency:** each `out_q_o[r][c]` is valid 3 clocks after its operands (the PE pipeline depth).

Verified with [tb_top_NxN](../testbenches/tb_top_NxN.md) at the default 2×2, driven at **full pipeline throughput** (a fresh operand every clock, checked against a pipeline-delayed golden): all 11 modes, three streaming passes — single-shot, accumulation (`seed + Σ` of `NUM_ACC` distinct tiles), and rectangle scaling (every `enabled_rows × enabled_cols`, disabled PEs held at 0).

Source: [top_NxN.sv](../../rtl/top_NxN.sv) — Diagram: [top_NxN](../../doc/diagrams/top_NxN.excalidraw)
