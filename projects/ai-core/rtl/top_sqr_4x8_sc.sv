// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Top-level Processing Element: Squaring split-cell array with 64 input
//   pairs and 3 accumulators.
//
//   Uses sqr_4x8_sc as the partial product generator, which decomposes each
//   8-bit B operand into two 4-bit halves and computes:
//     pp = (a[k]+b_lo[k])^2 + 16*(a[k]+b_hi[k])^2  per lane element
//
//   Function: out = sum_k[(a[k]+b_lo[k])^2 + 16*(a[k]+b_hi[k])^2] + sum(acc)
//
// Parameters:
//   IS_PIPELINED - 1 = 3-cycle latency; 0 = 2-cycle (no cpr_tree register)
//   MULT_TYPE    - unused; squaring does not use Booth encoding
//   SQR_TYPE     - 0 = sqr_s_5_bit_v0 (structural); 1 = sqr_s_5_bit_v1 (KMap flat)
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */
/* verilator lint_off UNUSEDPARAM */

`timescale 1 ns/1 ps

module top_sqr_4x8_sc #(
    parameter bit IS_PIPELINED = 1,
    parameter int MULT_TYPE    = 0,
    parameter int SQR_TYPE     = 0,

    localparam int IN_SIZE    = 64,
    localparam int IN_WIDTH_A = 4,
    localparam int IN_WIDTH_B = 8,
    localparam int ACC_SIZE   = 3,
    localparam int ACC_WIDTH  = 48,
    localparam int EXT_NUM    = 15,
    localparam int OUT_WIDTH  = ACC_WIDTH
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic [ ACC_WIDTH-1:0] acc_i       [0:ACC_SIZE-1],
    input  logic                  is_signed_i [ 0:EXT_NUM-1],
    input  logic                  is_shift_i  [ 0:EXT_NUM-1],
    input  logic [IN_WIDTH_A-1:0] a_i         [ 0:IN_SIZE-1],
    input  logic [IN_WIDTH_B-1:0] b_i         [ 0:IN_SIZE-1],
    output logic [ OUT_WIDTH-1:0] out_o
);

    localparam int NUM_LANES     = 8;
    localparam int NUM_SUB_LANES = 2;
    localparam int PP_SIZE       = 2 * NUM_SUB_LANES * NUM_LANES;
    localparam int CPR_IN_SIZE   = IN_SIZE / NUM_LANES;
    localparam int CPR_IN_WIDTH  = (IN_WIDTH_A + 1) * 2;
    localparam int PP_SUB_SHIFT  = 4;
    localparam int PP_WIDTH      = CPR_IN_WIDTH + $clog2(CPR_IN_SIZE) + 1 + PP_SUB_SHIFT;

    logic [IN_WIDTH_A-1:0] a  [0:IN_SIZE-1];
    logic [IN_WIDTH_B-1:0] b  [0:IN_SIZE-1];
    logic [  PP_WIDTH-1:0] pp [0:PP_SIZE-1];
    logic [ OUT_WIDTH-1:0] out;

    // -------------------------------------------------------------------------
    // Input registers
    // -------------------------------------------------------------------------
    ff_n #(
        .WIDTH(IN_WIDTH_A),
        .SIZE (IN_SIZE)
    ) ff_n_a_i (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .d_i   (a_i),
        .q_o   (a)
    );

    ff_n #(
        .WIDTH(IN_WIDTH_B),
        .SIZE (IN_SIZE)
    ) ff_n_b_i (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .d_i   (b_i),
        .q_o   (b)
    );

    // -------------------------------------------------------------------------
    // Partial product generator
    // -------------------------------------------------------------------------
    sqr_4x8_sc #(
        .SQR_TYPE(SQR_TYPE)
    ) sqr_4x8_sc_i (
        .a_i (a),
        .b_i (b),
        .pp_o(pp)
    );

    // -------------------------------------------------------------------------
    // Compression tree
    // -------------------------------------------------------------------------
    cpr_tree_4x8 #(
        .IS_PIPELINED(IS_PIPELINED),
        .PP_SIZE     (PP_SIZE),
        .PP_WIDTH    (PP_WIDTH),
        .ACC_SIZE    (ACC_SIZE)
    ) cpr_tree_4x8_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .acc_i      (acc_i),
        .is_signed_i(is_signed_i),
        .is_shift_i (is_shift_i),
        .pp_i       (pp),
        .out_o      (out)
    );

    // -------------------------------------------------------------------------
    // Output register
    // -------------------------------------------------------------------------
    ff #(
        .WIDTH(OUT_WIDTH)
    ) ff_out_i (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .d_i   (out),
        .q_o   (out_o)
    );

endmodule
