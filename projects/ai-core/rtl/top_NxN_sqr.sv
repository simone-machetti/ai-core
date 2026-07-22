// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   N x N grid of square Processing Elements - the top_NxN analogue for the
//   square variant. Same external interface and behaviour as top_NxN (per-row A,
//   per-col B, shared mode/sel_acc, per-PE acc and row/col enables); PE[r][c]
//   evaluates A[r] . B[c]. All the square-specific machinery is internal:
//
//     - ctrl_sqr   : one instance decodes the grid-wide mode into every control.
//     - const_sqr  : one instance holds the per-mode constant; its mode input is
//                    registered once ahead of it and its outputs once after, so
//                    the constant meets the tap at the acc stage in the same two
//                    register delays with one register fewer than registering the
//                    wide c / c_neg outputs twice.
//     - disp_array_a_sqr + pe_array_alpha_sqr : one pair per row, sharing the row
//                    clock-gate (en_row) - the dispatched A and the -alpha taps
//                    freeze together when the row is off.
//     - disp_array_b_sqr + pe_array_beta_sqr  : one pair per column, sharing the
//                    column clock-gate (en_col) - dispatched B and -beta freeze
//                    together when the column is off.
//     - pe_sqr[r][c] : the square PE core, fed the row's A/-alpha, the column's
//                    B/-beta and the shared const/controls.
//
//   Clock gating / scaling: en_row_i / en_col_i (active high) select an enabled
//   rectangle; a PE runs when en_row[r] & en_col[c]. One icg per row (dispatch A
//   + alpha), one per column (dispatch B + beta), one per PE. ctrl_sqr, the const
//   pipeline and the sel_acc pipeline run ungated. Each PE output is valid 3
//   clocks after its operands.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module top_NxN_sqr #(
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
    localparam int NUM_LEVEL   = 3,
    localparam int NUM_SHIFT   = 3,
    localparam int NUM_NEG     = 6,
    localparam int A_DP8_WIDTH = 64,
    localparam int B_DP8_WIDTH = 32,
    localparam int NUM_LANE    = 8,
    localparam int PE_WIDTH    = 20,
    localparam int NUM_L0      = 8,
    localparam int NUM_L1      = 4,
    localparam int NUM_L2      = 2,
    localparam int L0_TAP      = 19,
    localparam int L1_TAP      = 30,
    localparam int L2_TAP      = 38,
    localparam int L3_TAP      = 39,
    localparam int C_WIDTH     = 32,
    localparam int CNEG_WIDTH  = 8
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
    logic                 is_signed_a [ 0:NUM_DP8-1];
    logic                 is_signed_b [ 0:NUM_DP8-1];
    logic                 zero        [ 0:NUM_DP8-1];
    logic [  NUM_NEG-1:0] neg;
    logic [NUM_SHIFT-1:0] sel_shift;
    logic [NUM_LEVEL-1:0] en_level;
    logic [SEL_WIDTH-1:0] sel_out;
    logic [SEL_WIDTH-1:0] sel_const;
    logic                 prop_carry;

    ctrl_sqr ctrl_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .mode_i(mode_i),
        .sel_a_o(sel_a), .sel_b_o(sel_b),
        .is_signed_a_o(is_signed_a), .is_signed_b_o(is_signed_b),
        .zero_o(zero), .neg_o(neg), .sel_shift_o(sel_shift),
        .sel_out_o(sel_out), .sel_const_o(sel_const), .prop_carry_o(prop_carry),
        .en_level_o(en_level)
    );

    logic [MODE_WIDTH-1:0] mode_d [0:0], mode_q [0:0];
    logic [   C_WIDTH-1:0] c_o;
    logic [CNEG_WIDTH-1:0] c_neg_o;
    logic [   C_WIDTH-1:0] c_d  [0:0], c_q  [0:0];
    logic [CNEG_WIDTH-1:0] cn_d [0:0], cn_q [0:0];

    assign mode_d[0] = mode_i;

    reg_n #(.WIDTH(MODE_WIDTH), .SIZE(1)) reg_mode_i (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(mode_d), .q_o(mode_q));

    const_sqr const_sqr_i (
        .mode_i(mode_q[0]), .c_o(c_o), .c_neg_o(c_neg_o)
    );

    assign c_d[0]  = c_o;
    assign cn_d[0] = c_neg_o;

    reg_n #(.WIDTH(C_WIDTH),    .SIZE(1)) reg_c_i  (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(c_d),  .q_o(c_q));
    reg_n #(.WIDTH(CNEG_WIDTH), .SIZE(1)) reg_cn_i (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(cn_d), .q_o(cn_q));

    logic selacc_d [0:0];
    logic selacc_q1[0:0];
    logic selacc_q2[0:0];

    assign selacc_d[0] = sel_acc_i;

    reg_n #(.WIDTH(1), .SIZE(1)) reg_selacc1_i (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(selacc_d),  .q_o(selacc_q1));
    reg_n #(.WIDTH(1), .SIZE(1)) reg_selacc2_i (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(selacc_q1), .q_o(selacc_q2));

    logic [A_DP8_WIDTH-1:0] a_dp8_row   [0:NUM_ROW-1][0:NUM_DP8-1];
    logic [     L0_TAP-1:0] arow_l0_sum [0:NUM_ROW-1][ 0:NUM_L0-1], arow_l0_carry [0:NUM_ROW-1][0:NUM_L0-1];
    logic [     L1_TAP-1:0] arow_l1_sum [0:NUM_ROW-1][ 0:NUM_L1-1], arow_l1_carry [0:NUM_ROW-1][0:NUM_L1-1];
    logic [     L2_TAP-1:0] arow_l2_sum [0:NUM_ROW-1][ 0:NUM_L2-1], arow_l2_carry [0:NUM_ROW-1][0:NUM_L2-1];
    logic [     L3_TAP-1:0] arow_l3_sum [0:NUM_ROW-1], arow_l3_carry [0:NUM_ROW-1];

    logic [B_DP8_WIDTH-1:0] b_dp8_col   [0:NUM_COL-1][0:NUM_DP8-1];
    logic [     L0_TAP-1:0] bcol_l0_sum [0:NUM_COL-1][ 0:NUM_L0-1], bcol_l0_carry [0:NUM_COL-1][0:NUM_L0-1];
    logic [     L1_TAP-1:0] bcol_l1_sum [0:NUM_COL-1][ 0:NUM_L1-1], bcol_l1_carry [0:NUM_COL-1][0:NUM_L1-1];
    logic [     L2_TAP-1:0] bcol_l2_sum [0:NUM_COL-1][ 0:NUM_L2-1], bcol_l2_carry [0:NUM_COL-1][0:NUM_L2-1];
    logic [     L3_TAP-1:0] bcol_l3_sum [0:NUM_COL-1], bcol_l3_carry [0:NUM_COL-1];

    genvar r, c;
    generate
        for (r = 0; r < NUM_ROW; r++) begin : gen_row
            logic clk_a;
            icg icg_a_i (.clk_i(clk_i), .en_i(en_row_i[r]), .clk_o(clk_a));

            disp_array_a_sqr disp_array_a_sqr_i (
                .clk_i(clk_a), .rst_ni(rst_ni), .pe_in_a_i(in_a_i[r]),
                .sel_a_i(sel_a), .is_signed_a_i(is_signed_a), .zero_i(zero),
                .a_dp8_o(a_dp8_row[r])
            );

            pe_array_alpha_sqr pe_array_alpha_sqr_i (
                .clk_i(clk_a), .rst_ni(rst_ni),
                .a_dp8_i(a_dp8_row[r]), .is_signed_b_i(is_signed_b),
                .neg_i(neg), .sel_shift_i(sel_shift), .en_level_i(en_level),
                .l0_sum_o(arow_l0_sum[r]), .l0_carry_o(arow_l0_carry[r]),
                .l1_sum_o(arow_l1_sum[r]), .l1_carry_o(arow_l1_carry[r]),
                .l2_sum_o(arow_l2_sum[r]), .l2_carry_o(arow_l2_carry[r]),
                .l3_sum_o(arow_l3_sum[r]), .l3_carry_o(arow_l3_carry[r])
            );
        end

        for (c = 0; c < NUM_COL; c++) begin : gen_col
            logic clk_b;
            icg icg_b_i (.clk_i(clk_i), .en_i(en_col_i[c]), .clk_o(clk_b));

            disp_array_b_sqr disp_array_b_sqr_i (
                .clk_i(clk_b), .rst_ni(rst_ni), .pe_in_b_i(in_b_i[c]),
                .sel_b_i(sel_b), .is_signed_b_i(is_signed_b), .zero_i(zero),
                .b_dp8_o(b_dp8_col[c])
            );

            pe_array_beta_sqr pe_array_beta_sqr_i (
                .clk_i(clk_b), .rst_ni(rst_ni),
                .b_dp8_i(b_dp8_col[c]), .is_signed_a_i(is_signed_a), .zero_i(zero),
                .neg_i(neg), .sel_shift_i(sel_shift), .en_level_i(en_level),
                .l0_sum_o(bcol_l0_sum[c]), .l0_carry_o(bcol_l0_carry[c]),
                .l1_sum_o(bcol_l1_sum[c]), .l1_carry_o(bcol_l1_carry[c]),
                .l2_sum_o(bcol_l2_sum[c]), .l2_carry_o(bcol_l2_carry[c]),
                .l3_sum_o(bcol_l3_sum[c]), .l3_carry_o(bcol_l3_carry[c])
            );
        end

        for (r = 0; r < NUM_ROW; r++) begin : gen_pe_row
            for (c = 0; c < NUM_COL; c++) begin : gen_pe_col
                logic en_pe;
                logic clk_pe;

                assign en_pe = en_row_i[r] & en_col_i[c];
                icg icg_pe_i (.clk_i(clk_i), .en_i(en_pe), .clk_o(clk_pe));

                pe_sqr pe_sqr_i (
                    .clk_i(clk_pe), .rst_ni(rst_ni),
                    .a_dp8_i(a_dp8_row[r]), .b_dp8_i(b_dp8_col[c]),
                    .en_i(en_pe), .neg_i(neg), .sel_shift_i(sel_shift), .en_level_i(en_level),
                    .a_l0_sum_i(arow_l0_sum[r]), .a_l0_carry_i(arow_l0_carry[r]),
                    .a_l1_sum_i(arow_l1_sum[r]), .a_l1_carry_i(arow_l1_carry[r]),
                    .a_l2_sum_i(arow_l2_sum[r]), .a_l2_carry_i(arow_l2_carry[r]),
                    .a_l3_sum_i(arow_l3_sum[r]), .a_l3_carry_i(arow_l3_carry[r]),
                    .b_l0_sum_i(bcol_l0_sum[c]), .b_l0_carry_i(bcol_l0_carry[c]),
                    .b_l1_sum_i(bcol_l1_sum[c]), .b_l1_carry_i(bcol_l1_carry[c]),
                    .b_l2_sum_i(bcol_l2_sum[c]), .b_l2_carry_i(bcol_l2_carry[c]),
                    .b_l3_sum_i(bcol_l3_sum[c]), .b_l3_carry_i(bcol_l3_carry[c]),
                    .c_i(c_q[0]), .c_neg_i(cn_q[0]),
                    .acc_i(acc_i[r][c]),
                    .sel_out_i(sel_out), .sel_acc_i(selacc_q2[0]),
                    .sel_const_i(sel_const), .prop_carry_i(prop_carry),
                    .out_o(out_q_o[r][c])
                );
            end
        end
    endgenerate

endmodule
