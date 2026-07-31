// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   N x N grid of square + BFP Processing Elements - the top_NxN_sqr analogue
//   with the BFP exponent sideband, or top_NxN_bfp with the square datapath. Same
//   external interface and behaviour as top_NxN_bfp (per-row A mantissa+exponent,
//   per-col B mantissa+exponent, shared mode/sel_acc, per-PE acc/acc_exp and
//   row/col enables); PE[r][c] evaluates A[r] . B[c] in block floating point via
//   the square identity. All the square-BFP machinery is internal:
//
//     - ctrl_sqr   : one instance decodes the grid-wide mode into every control
//                    (reused verbatim - it already drops ctr_l/ctr_h and emits the
//                    zero the BFP exponent dispatchers need; sel_const is unused,
//                    the constant is per-DP8 upstream).
//     - const_sqr_bfp : one instance holds the per-DP8 constant; its mode input is
//                    registered once ahead of it so the constant meets the singly-
//                    registered dispatched operands at the L0 combine (one register
//                    fewer than const_sqr, which reaches the later acc stage).
//     - disp_array_a_sqr + disp_array_exp_a_sqr_bfp + pe_array_alpha_sqr_bfp :
//                    one set per row, sharing the row clock-gate (en_row) - the
//                    dispatched A mantissa/exponent and, combinationally from the
//                    registered A, the -alpha carry-save pairs freeze together.
//     - disp_array_b_sqr + disp_array_exp_b_sqr_bfp + pe_array_beta_sqr_bfp :
//                    one set per column, sharing the column clock-gate (en_col).
//     - pe_sqr_bfp[r][c] : the square-BFP PE core, fed the row's A/-alpha/expA,
//                    the column's B/-beta/expB, the shared const_dp8 and controls.
//
//   The alpha/beta generators are tree-less and combinational (their pipeline
//   register lives in pe_array_sqr_bfp's L0); fed by the clk-gated dispatch
//   register they still freeze with their row/column. Clock gating / scaling is
//   identical to top_NxN_bfp: en_row_i / en_col_i (active high), a PE runs when
//   en_row[r] & en_col[c], one icg per PE (gates clock, masks operands) and one
//   per row/column dispatch set. The raw accumulator mantissa (out_q_o) and its
//   7-bit product-domain scale (out_exp_o) leave un-normalized; out_exp_o shares
//   the acc_exp_i seed format, so an output can feed straight back as a seed. Each
//   PE output is valid 3 clocks after its operands.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module top_NxN_sqr_bfp #(
    parameter  int N            = 2,
    localparam int NUM_ROW      = N,
    localparam int NUM_COL      = N,
    localparam int NUM_BLK      = 4,
    localparam int BLK_WIDTH    = 64,
    localparam int PE_IN_WIDTH  = NUM_BLK * BLK_WIDTH,
    localparam int EXP_IN_WIDTH = 6,
    localparam int EXP_WIDTH    = 7,
    localparam int EXP_A_WIDTH  = NUM_BLK * EXP_IN_WIDTH,
    localparam int EXP_B_WIDTH  = NUM_BLK * 2 * EXP_IN_WIDTH,
    localparam int MODE_WIDTH   = 4,
    localparam int NUM_PAIR     = 8,
    localparam int NUM_DP8      = 16,
    localparam int SEL_WIDTH    = 2,
    localparam int NUM_LEVEL    = 3,
    localparam int NUM_SHIFT    = 3,
    localparam int NUM_NEG      = 6,
    localparam int A_DP8_WIDTH  = 64,
    localparam int B_DP8_WIDTH  = 32,
    localparam int DP8_WIDTH    = 18,
    localparam int NUM_LANE     = 8,
    localparam int PE_WIDTH     = 20
)(
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic [ PE_IN_WIDTH-1:0] in_a_i     [0:NUM_ROW-1],
    input  logic [ PE_IN_WIDTH-1:0] in_b_i     [0:NUM_COL-1],
    input  logic [ EXP_A_WIDTH-1:0] in_exp_a_i [0:NUM_ROW-1],
    input  logic [ EXP_B_WIDTH-1:0] in_exp_b_i [0:NUM_COL-1],
    input  logic [  MODE_WIDTH-1:0] mode_i,
    input  logic                    sel_acc_i,
    input  logic [    PE_WIDTH-1:0] acc_i      [0:NUM_ROW-1][0:NUM_COL-1][0:NUM_LANE-1],
    input  logic [   EXP_WIDTH-1:0] acc_exp_i  [0:NUM_ROW-1][0:NUM_COL-1][0:NUM_LANE-1],
    input  logic                    en_row_i   [0:NUM_ROW-1],
    input  logic                    en_col_i   [0:NUM_COL-1],
    output logic [    PE_WIDTH-1:0] out_q_o    [0:NUM_ROW-1][0:NUM_COL-1][0:NUM_LANE-1],
    output logic [   EXP_WIDTH-1:0] out_exp_o  [0:NUM_ROW-1][0:NUM_COL-1][0:NUM_LANE-1]
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
    logic                 prop_carry;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [SEL_WIDTH-1:0] sel_const;
    /* verilator lint_on UNUSEDSIGNAL */

    ctrl_sqr ctrl_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .mode_i(mode_i),
        .sel_a_o(sel_a), .sel_b_o(sel_b),
        .is_signed_a_o(is_signed_a), .is_signed_b_o(is_signed_b),
        .zero_o(zero), .neg_o(neg), .sel_shift_o(sel_shift),
        .sel_out_o(sel_out), .en_level_o(en_level),
        .sel_const_o(sel_const), .prop_carry_o(prop_carry)
    );

    logic [MODE_WIDTH-1:0] mode_d [0:0], mode_q [0:0];
    logic [ DP8_WIDTH-1:0] const_dp8 [0:NUM_DP8-1];

    assign mode_d[0] = mode_i;

    reg_n #(.WIDTH(MODE_WIDTH), .SIZE(1)) reg_mode_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(mode_d), .q_o(mode_q)
    );

    const_sqr_bfp const_sqr_bfp_i (
        .mode_i(mode_q[0]), .const_dp8_o(const_dp8)
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

    logic [ A_DP8_WIDTH-1:0] a_dp8_row      [0:NUM_ROW-1][0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0] exp_a_dp8_row  [0:NUM_ROW-1][0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0] alpha_sum_row  [0:NUM_ROW-1][0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0] alpha_carry_row[0:NUM_ROW-1][0:NUM_DP8-1];

    logic [ B_DP8_WIDTH-1:0] b_dp8_col      [0:NUM_COL-1][0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0] exp_b_dp8_col  [0:NUM_COL-1][0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0] beta_sum_col   [0:NUM_COL-1][0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0] beta_carry_col [0:NUM_COL-1][0:NUM_DP8-1];

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

            disp_array_exp_a_sqr_bfp disp_array_exp_a_sqr_bfp_i (
                .clk_i(clk_a), .rst_ni(rst_ni), .pe_exp_a_i(in_exp_a_i[r]),
                .sel_a_i(sel_a), .zero_i(zero),
                .exp_a_dp8_o(exp_a_dp8_row[r])
            );

            pe_array_alpha_sqr_bfp pe_array_alpha_sqr_bfp_i (
                .a_dp8_i(a_dp8_row[r]), .is_signed_b_i(is_signed_b),
                .alpha_sum_o(alpha_sum_row[r]), .alpha_carry_o(alpha_carry_row[r])
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

            disp_array_exp_b_sqr_bfp disp_array_exp_b_sqr_bfp_i (
                .clk_i(clk_b), .rst_ni(rst_ni), .pe_exp_b_i(in_exp_b_i[c]),
                .sel_b_i(sel_b), .zero_i(zero),
                .exp_b_dp8_o(exp_b_dp8_col[c])
            );

            pe_array_beta_sqr_bfp pe_array_beta_sqr_bfp_i (
                .b_dp8_i(b_dp8_col[c]), .is_signed_a_i(is_signed_a), .zero_i(zero),
                .beta_sum_o(beta_sum_col[c]), .beta_carry_o(beta_carry_col[c])
            );
        end

        for (r = 0; r < NUM_ROW; r++) begin : gen_pe_row
            for (c = 0; c < NUM_COL; c++) begin : gen_pe_col
                logic en_pe;
                logic clk_pe;

                assign en_pe = en_row_i[r] & en_col_i[c];
                icg icg_pe_i (.clk_i(clk_i), .en_i(en_pe), .clk_o(clk_pe));

                pe_sqr_bfp pe_sqr_bfp_i (
                    .clk_i        (clk_pe),
                    .rst_ni       (rst_ni),
                    .a_dp8_i      (a_dp8_row[r]),
                    .b_dp8_i      (b_dp8_col[c]),
                    .exp_a_dp8_i  (exp_a_dp8_row[r]),
                    .exp_b_dp8_i  (exp_b_dp8_col[c]),
                    .alpha_sum_i  (alpha_sum_row[r]),
                    .alpha_carry_i(alpha_carry_row[r]),
                    .beta_sum_i   (beta_sum_col[c]),
                    .beta_carry_i (beta_carry_col[c]),
                    .const_dp8_i  (const_dp8),
                    .en_i         (en_pe),
                    .en_level_i   (en_level),
                    .neg_i        (neg),
                    .zero_i       (zero),
                    .sel_shift_i  (sel_shift),
                    .acc_i        (acc_i[r][c]),
                    .acc_exp_i    (acc_exp_i[r][c]),
                    .sel_out_i    (sel_out),
                    .sel_acc_i    (selacc_q2[0]),
                    .prop_carry_i (prop_carry),
                    .out_o        (out_q_o[r][c]),
                    .out_exp_o    (out_exp_o[r][c])
                );
            end
        end
    endgenerate

endmodule
