// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Baseline N x N grid of Processing Elements - the top level that tiles N*N
//   top_pe_bas PEs (N is the parameter, default 2). Operand A is shared per row
//   (in_a_i[r] drives every PE in row r) and operand B along each column
//   (in_b_i[c] drives every PE in column c), so PE[r][c] evaluates A[r] . B[c].
//   The mode and the accumulate select are broadcast to all PEs; the external
//   accumulator word and the registered output are per PE (no sharing).
//
//   Each PE owns a dedicated integrated clock-gating cell (icg) driven by
//   clk_gate_i[r][c] (1 = stop that PE's clock), so an idle PE can be frozen
//   independently while the rest keep running; the asynchronous reset rst_ni
//   reaches every PE ungated. Purely structural - fan-out wiring plus N*N icg +
//   N*N top_pe_bas, no top-level logic. Each PE output is valid 3 clocks after
//   its operands, the top_pe_bas pipeline depth.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module top_NxN_bas #(
    parameter  int N           = 2,
    localparam int NUM_ROW     = N,
    localparam int NUM_COL     = N,
    localparam int NUM_BLK     = 4,
    localparam int BLK_WIDTH   = 64,
    localparam int PE_IN_WIDTH = NUM_BLK * BLK_WIDTH,
    localparam int MODE_WIDTH  = 4,
    localparam int NUM_LANE    = 8,
    localparam int PE_WIDTH    = 20
)(
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [PE_IN_WIDTH-1:0] in_a_i     [0:NUM_ROW-1],
    input  logic [PE_IN_WIDTH-1:0] in_b_i     [0:NUM_COL-1],
    input  logic [ MODE_WIDTH-1:0] mode_i,
    input  logic                   sel_acc_i,
    input  logic [   PE_WIDTH-1:0] acc_i      [0:NUM_ROW-1][0:NUM_COL-1][0:NUM_LANE-1],
    input  logic                   clk_gate_i [0:NUM_ROW-1][0:NUM_COL-1],
    output logic [   PE_WIDTH-1:0] out_q_o    [0:NUM_ROW-1][0:NUM_COL-1][0:NUM_LANE-1]
);

    genvar r, c;

    generate
        for (r = 0; r < NUM_ROW; r++) begin : gen_row
            for (c = 0; c < NUM_COL; c++) begin : gen_col

                logic pe_clk;

                icg icg_i (
                    .clk_i(clk_i),
                    .en_i (~clk_gate_i[r][c]),
                    .clk_o(pe_clk)
                );

                top_pe_bas top_pe_bas_i (
                    .clk_i    (pe_clk),
                    .rst_ni   (rst_ni),
                    .pe_in_a_i(in_a_i[r]),
                    .pe_in_b_i(in_b_i[c]),
                    .mode_i   (mode_i),
                    .sel_acc_i(sel_acc_i),
                    .acc_i    (acc_i[r][c]),
                    .pe_out_o (out_q_o[r][c])
                );

            end
        end
    endgenerate

endmodule
