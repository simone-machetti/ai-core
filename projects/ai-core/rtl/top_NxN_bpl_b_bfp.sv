// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   BFP N x N grid of Processing Elements, bit-plane B build - the top_NxN_bfp
//   variant built on the bit-plane row dispatch and PE (disp_array_a_bpl_b_bfp,
//   pe_bpl_b_bfp). Tiles N*N cores; operand A (mantissa + exponent) is shared per
//   row and operand B per column, so PE[r][c] evaluates A[r] . B[c] in block
//   floating point, with the same values as top_NxN_bfp.
//
//   Each row's dispatcher also emits the per-DP8 pairwise A sums the bit-plane
//   cores consume, so those adders are paid once per row rather than once per PE
//   - one gate per DP8 pair, since both DP8s of a pair share an A block and a
//   signedness flag. Because the dispatcher resolves A to signed values, ctrl's
//   is_signed_a feeds the N dispatchers and never reaches the PEs; the column
//   route is the plain disp_array_b and B reaches the PEs as raw int4.
//
//   is_signed_b is masked here for the DP8s the mode leaves idle, taken from
//   ctrl's zero gate codes: an idle DP8 multiplies a zero B, so its result does
//   not depend on the flag, and clearing it keeps that result an exact zero for
//   the BFP alignment downstream.
//
//   Everything else is top_NxN_bfp: ctrl, disp_array_b, both exponent
//   dispatchers, the clock-gating structure, the sel_acc pipeline, the pipeline
//   depth and the port list.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module top_NxN_bpl_b_bfp #(
    parameter  int N                 = 2,
    localparam int NUM_ROW           = N,
    localparam int NUM_COL           = N,
    localparam int NUM_BLK           = 4,
    localparam int BLK_WIDTH         = 64,
    localparam int PE_IN_WIDTH       = NUM_BLK * BLK_WIDTH,
    localparam int EXP_IN_WIDTH      = 6,
    localparam int EXP_WIDTH         = 7,
    localparam int EXP_A_WIDTH       = NUM_BLK * EXP_IN_WIDTH,
    localparam int EXP_B_WIDTH       = NUM_BLK * 2 * EXP_IN_WIDTH,
    localparam int MODE_WIDTH        = 4,
    localparam int NUM_PAIR          = 8,
    localparam int NUM_DP8           = 16,
    localparam int SEL_WIDTH         = 2,
    localparam int OP_WIDTH          = 2,
    localparam logic [1:0] GATE_ZERO = 2'b01,
    localparam int NUM_LEVEL         = 3,
    localparam int NUM_SHIFT         = 3,
    localparam int LANES             = 8,
    localparam int IN_WIDTH_A        = 9,
    localparam int IN_WIDTH_B        = 4,
    localparam int SUM_WIDTH         = 10,
    localparam int NUM_A_SUM         = LANES / 2,
    localparam int A_DP8_WIDTH       = LANES * IN_WIDTH_A,
    localparam int B_DP8_WIDTH       = LANES * IN_WIDTH_B,
    localparam int A_SUM_WIDTH       = NUM_A_SUM * SUM_WIDTH,
    localparam int NUM_LANE          = 8,
    localparam int PE_WIDTH          = 20
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

    logic [SEL_WIDTH-1:0] sel_a         [0:NUM_PAIR-1];
    logic [SEL_WIDTH-1:0] sel_b         [0:NUM_PAIR-1];
    logic [ OP_WIDTH-1:0] ctr_l         [0:NUM_PAIR-1];
    logic [ OP_WIDTH-1:0] ctr_h         [0:NUM_PAIR-1];
    logic                 is_signed_a   [ 0:NUM_DP8-1];
    logic                 is_signed_b_g [ 0:NUM_DP8-1];
    logic                 is_signed_b   [ 0:NUM_DP8-1];
    logic [NUM_SHIFT-1:0] sel_shift;
    logic [NUM_LEVEL-1:0] en_level;
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
        .en_level_o   (en_level),
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

    genvar p;
    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_idle_mask
            assign is_signed_b_g[2*p+0] = is_signed_b[2*p+0] & (ctr_h[p] != GATE_ZERO);
            assign is_signed_b_g[2*p+1] = is_signed_b[2*p+1] & (ctr_l[p] != GATE_ZERO);
        end
    endgenerate

    logic [ A_DP8_WIDTH-1:0] a_dp8_row     [0:NUM_ROW-1][0:NUM_DP8-1];
    logic [ A_SUM_WIDTH-1:0] a_sum_dp8_row [0:NUM_ROW-1][0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0] exp_a_dp8_row [0:NUM_ROW-1][0:NUM_DP8-1];

    genvar r, c;
    generate
        for (r = 0; r < NUM_ROW; r++) begin : gen_disp_a
            logic clk_a;
            icg icg_a_i (
                .clk_i(clk_i), .en_i(en_row_i[r]), .clk_o(clk_a)
            );
            disp_array_a_bpl_b_bfp disp_array_a_bpl_b_bfp_i (
                .clk_i    (clk_a),
                .rst_ni   (rst_ni),
                .pe_in_a_i(in_a_i[r]),
                .sel_a_i  (sel_a),
                .is_signed_a_i(is_signed_a),
                .a_dp8_o  (a_dp8_row[r]),
                .a_sum_dp8_o(a_sum_dp8_row[r])
            );
            disp_array_exp_a_bfp disp_array_exp_a_bfp_i (
                .clk_i      (clk_a),
                .rst_ni     (rst_ni),
                .pe_exp_a_i (in_exp_a_i[r]),
                .sel_a_i    (sel_a),
                .ctr_l_i    (ctr_l),
                .ctr_h_i    (ctr_h),
                .exp_a_dp8_o(exp_a_dp8_row[r])
            );
        end
    endgenerate

    logic [ B_DP8_WIDTH-1:0] b_dp8_col     [0:NUM_COL-1][0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0] exp_b_dp8_col [0:NUM_COL-1][0:NUM_DP8-1];

    generate
        for (c = 0; c < NUM_COL; c++) begin : gen_disp_b
            logic clk_b;
            icg icg_b_i (
                .clk_i(clk_i), .en_i(en_col_i[c]), .clk_o(clk_b)
            );
            disp_array_b disp_array_b_i (
                .clk_i        (clk_b),
                .rst_ni       (rst_ni),
                .pe_in_b_i    (in_b_i[c]),
                .sel_b_i      (sel_b),
                .ctr_l_i      (ctr_l),
                .ctr_h_i      (ctr_h),
                .b_dp8_o      (b_dp8_col[c])
            );
            disp_array_exp_b_bfp disp_array_exp_b_bfp_i (
                .clk_i      (clk_b),
                .rst_ni     (rst_ni),
                .pe_exp_b_i (in_exp_b_i[c]),
                .sel_b_i    (sel_b),
                .ctr_l_i    (ctr_l),
                .ctr_h_i    (ctr_h),
                .exp_b_dp8_o(exp_b_dp8_col[c])
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

                pe_bpl_b_bfp pe_bpl_b_bfp_i (
                    .clk_i        (clk_pe),
                    .rst_ni       (rst_ni),
                    .a_dp8_i      (a_dp8_row[r]),
                    .a_sum_dp8_i  (a_sum_dp8_row[r]),
                    .b_dp8_i      (b_dp8_col[c]),
                    .exp_a_dp8_i  (exp_a_dp8_row[r]),
                    .exp_b_dp8_i  (exp_b_dp8_col[c]),
                    .en_i         (en_pe),
                    .is_signed_b_i(is_signed_b_g),
                    .sel_shift_i  (sel_shift),
                    .en_level_i   (en_level),
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
