// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Baseline N x N grid of Processing Elements - the top level that tiles N*N pe
//   cores (N is the parameter, default 2). Operand A is shared per row (in_a_i[r]
//   drives every PE in row r) and operand B along each column (in_b_i[c] drives
//   every PE in column c), so PE[r][c] evaluates A[r] . B[c].
//
//   The redundant per-PE control and dispatch are hoisted and shared:
//     - ctrl          : one instance decodes the grid-wide mode for all PEs.
//     - disp_array_a  : one per row; registers A[r] and broadcasts the dispatched
//                       A to that row's PEs.
//     - disp_array_b  : one per column; registers B[c], applies the B gating, and
//                       broadcasts the dispatched B to that column's PEs.
//     - sel_acc       : pipelined once here (two registers, shared) since it is a
//                       grid-wide runtime control.
//   acc and the registered output stay per PE.
//
//   Clock gating / scaling: row/column enables en_row_i / en_col_i (active high).
//   A PE is enabled when its row AND column are enabled (en_row[r] & en_col[c]),
//   so the active region is any enabled_rows x enabled_cols rectangle - the grid
//   scales down from N x N. One icg per PE gates its clock and the same enable
//   AND-masks its operands (a disabled PE stops toggling and holds); one icg per
//   disp_array_a / disp_array_b freezes a fully-disabled row/column's dispatch.
//   ctrl and the sel_acc pipeline run ungated. Each PE output is valid 3 clocks
//   after its operands (the pipeline depth).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module top_NxN #(
    parameter  int N           = 2,
    localparam int NUM_ROW     = N,
    localparam int NUM_COL     = N,
    localparam int NUM_BLK     = 4,
    localparam int BLK_WIDTH   = 64,
    localparam int PE_IN_WIDTH = NUM_BLK * BLK_WIDTH,
    localparam int MODE_WIDTH  = 4,
    localparam int NUM_PAIR    = 8,
    localparam int NUM_DP8     = 16,
    localparam int SEL_WIDTH   = 2,
    localparam int OP_WIDTH    = 2,
    localparam int NUM_SHIFT   = 3,
    localparam int A_DP8_WIDTH = 64,
    localparam int B_DP8_WIDTH = 32,
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
    input  logic                   en_row_i   [0:NUM_ROW-1],
    input  logic                   en_col_i   [0:NUM_COL-1],
    output logic [   PE_WIDTH-1:0] out_q_o    [0:NUM_ROW-1][0:NUM_COL-1][0:NUM_LANE-1]
);

    logic [SEL_WIDTH-1:0] sel_a       [0:NUM_PAIR-1];
    logic [SEL_WIDTH-1:0] sel_b       [0:NUM_PAIR-1];
    logic [ OP_WIDTH-1:0] ctr_l       [0:NUM_PAIR-1];
    logic [ OP_WIDTH-1:0] ctr_h       [0:NUM_PAIR-1];
    logic                 is_signed_a [0:NUM_DP8-1];
    logic                 is_signed_b [0:NUM_DP8-1];
    logic [NUM_SHIFT-1:0] sel_shift;
    logic [SEL_WIDTH-1:0] sel_out;
    logic                 prop_carry;

    ctrl ctrl_i (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .mode_i       (mode_i),
        .sel_a_o      (sel_a),
        .sel_b_o      (sel_b),
        .ctr_l_o      (ctr_l),
        .ctr_h_o      (ctr_h),
        .is_signed_a_o(is_signed_a),
        .is_signed_b_o(is_signed_b),
        .sel_shift_o  (sel_shift),
        .sel_out_o    (sel_out),
        .prop_carry_o (prop_carry)
    );

    logic selacc_d [0:0];
    logic selacc_q1[0:0];
    logic selacc_q2[0:0];

    assign selacc_d[0] = sel_acc_i;

    reg_n #(.WIDTH(1), .SIZE(1)) reg_selacc1_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selacc_d),  .q_o(selacc_q1)
    );
    reg_n #(.WIDTH(1), .SIZE(1)) reg_selacc2_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selacc_q1), .q_o(selacc_q2)
    );

    logic [A_DP8_WIDTH-1:0] a_dp8_row [0:NUM_ROW-1][0:NUM_DP8-1];

    genvar r, c;
    generate
        for (r = 0; r < NUM_ROW; r++) begin : gen_disp_a
            logic clk_a;
            icg icg_a_i (
                .clk_i(clk_i), .en_i(en_row_i[r]), .clk_o(clk_a)
            );
            disp_array_a disp_array_a_i (
                .clk_i    (clk_a),
                .rst_ni   (rst_ni),
                .pe_in_a_i(in_a_i[r]),
                .sel_a_i  (sel_a),
                .a_dp8_o  (a_dp8_row[r])
            );
        end
    endgenerate

    logic [B_DP8_WIDTH-1:0] b_dp8_col [0:NUM_COL-1][0:NUM_DP8-1];

    generate
        for (c = 0; c < NUM_COL; c++) begin : gen_disp_b
            logic clk_b;
            icg icg_b_i (
                .clk_i(clk_i), .en_i(en_col_i[c]), .clk_o(clk_b)
            );
            disp_array_b disp_array_b_i (
                .clk_i    (clk_b),
                .rst_ni   (rst_ni),
                .pe_in_b_i(in_b_i[c]),
                .sel_b_i  (sel_b),
                .ctr_l_i  (ctr_l),
                .ctr_h_i  (ctr_h),
                .b_dp8_o  (b_dp8_col[c])
            );
        end
    endgenerate

    generate
        for (r = 0; r < NUM_ROW; r++) begin : gen_pe_row
            for (c = 0; c < NUM_COL; c++) begin : gen_pe_col
                logic en_pe;
                logic clk_pe;

                assign en_pe = en_row_i[r] & en_col_i[c];

                icg icg_pe_i (
                    .clk_i(clk_i), .en_i(en_pe), .clk_o(clk_pe)
                );

                pe pe_i (
                    .clk_i        (clk_pe),
                    .rst_ni       (rst_ni),
                    .a_dp8_i      (a_dp8_row[r]),
                    .b_dp8_i      (b_dp8_col[c]),
                    .en_i         (en_pe),
                    .is_signed_a_i(is_signed_a),
                    .is_signed_b_i(is_signed_b),
                    .sel_shift_i  (sel_shift),
                    .acc_i        (acc_i[r][c]),
                    .sel_out_i    (sel_out),
                    .sel_acc_i    (selacc_q2[0]),
                    .prop_carry_i (prop_carry),
                    .out_o        (out_q_o[r][c])
                );
            end
        end
    endgenerate

endmodule
