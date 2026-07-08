# PE Grid (baseline)

`top_NxN_bas` — the baseline **N × N grid** of Processing Elements: it tiles N² [top_pe_bas](./top_pe_bas.md) PEs into a square array, sharing operand A along each row and operand B along each column, so PE[r][c] evaluates `A[r] · B[c]`. `N` is a parameter — **default 2** for a fast build; the full chip uses `N = 8`.

## Purpose

An outer-product tiling: with A broadcast per row and B per column, the N² PEs cover every `A[row] · B[col]` pairing in parallel, each an independent matmul in one of the 11 modes. `mode` and `sel_acc` are shared across the whole array; the external accumulator word `acc` and the registered output `out_q` are per PE. Every PE owns a dedicated [icg](../modules/icg.md) so an idle PE can be clock-gated independently to save power. The module is purely structural — fan-out wiring plus N² ICGs and N² PEs, no top-level logic.

## Parameters

| Parameter | Default | Meaning                                               |
| --------- | ------- | ----------------------------------------------------- |
| `N`       | 2       | Grid side — the array is `N × N` PEs (chip: `N = 8`). |

Derived `localparam`s: `NUM_ROW = NUM_COL = N`, `PE_IN_WIDTH = 256`, `MODE_WIDTH = 4`, `NUM_LANE = 8`, `PE_WIDTH = 20`.

## Interface

| Signal                     | Dir | Width    | Description                                         |
| -------------------------- | --- | -------- | --------------------------------------------------- |
| `clk_i`, `rst_ni`          | in  | 1        | Clock and asynchronous active-low reset (ungated).  |
| `in_a_i[0:N-1]`            | in  | 256 each | Operand A, one per row (shared across the row).     |
| `in_b_i[0:N-1]`            | in  | 256 each | Operand B, one per column (shared down the column). |
| `mode_i`                   | in  | 4        | Operating mode, broadcast to all PEs.               |
| `sel_acc_i`                | in  | 1        | Accumulate select, broadcast to all PEs.            |
| `acc_i[0:N-1][0:N-1]`      | in  | 8 × 20   | External accumulator word, per PE.                  |
| `clk_gate_i[0:N-1][0:N-1]` | in  | 1        | Per-PE clock gate — `1` stops that PE's clock.      |
| `out_q_o[0:N-1][0:N-1]`    | out | 8 × 20   | Per-PE registered result.                           |

## Instantiation

```systemverilog
top_NxN_bas #(.N(8)) grid_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .in_a_i(in_a), .in_b_i(in_b),
    .mode_i(mode), .sel_acc_i(sel_acc),
    .acc_i(acc), .clk_gate_i(clk_gate),
    .out_q_o(out_q)
);
```

## Internal logic

One generate nest builds the array; each cell is an ICG feeding a PE:

```systemverilog
for (r = 0; r < NUM_ROW; r++) for (c = 0; c < NUM_COL; c++) begin
    logic pe_clk;
    icg icg_i (.clk_i(clk_i), .en_i(~clk_gate_i[r][c]), .clk_o(pe_clk));
    top_pe_bas top_pe_bas_i (
        .clk_i(pe_clk), .rst_ni(rst_ni),
        .pe_in_a_i(in_a_i[r]), .pe_in_b_i(in_b_i[c]),
        .mode_i(mode_i), .sel_acc_i(sel_acc_i),
        .acc_i(acc_i[r][c]), .pe_out_o(out_q_o[r][c]) );
end
```

- **Fan-out:** `in_a_i[r]` reaches every PE in row `r`; `in_b_i[c]` every PE in column `c`.
- **Clock gating:** `clk_gate_i[r][c] = 1` drives the PE's ICG enable low, freezing that PE (its registers hold, no dynamic power) while its neighbours keep running. `rst_ni` is not gated, so a frozen PE still resets.
- **Latency:** each `out_q_o[r][c]` is valid 3 clocks after its operands (the `top_pe_bas` pipeline depth).

Verified with [tb_top_NxN_bas](../testbenches/tb_top_NxN_bas.md) at the default 2×2: all 11 modes, one-shot, accumulation, and clock-gating (quarter / half / three-quarters / all).

Source: [top_NxN_bas.sv](../../rtl/top_NxN_bas.sv) — Diagram: [top_NxN_bas](../../doc/diagrams/top_NxN_bas.excalidraw)
