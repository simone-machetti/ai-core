// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Top-level Processing Element: Winograd 4-bit × 8-bit multiply-accumulate
//   array with 64 lanes and 3 accumulators.
//
//   Uses the Winograd identity to reduce the multiplier count by half: each
//   adjacent input pair (a[i], b[i]) and (a[i+1], b[i+1]) shares one multiply:
//     product_i = (a[i+1] + b[i]) * (a[i] + b[i+1])
//
//   Function: out = sum_{i=0,2,...,62}[(a[i+1]+b[i])*(a[i]+b[i+1])] + sum(acc)
//
// Parameters:
//   IS_PIPELINED - 1 = 3-cycle latency; 0 = 2-cycle (no cpr_tree register)
//   MULT_TYPE    - 0 = Radix-4 Booth, 1 = Radix-8 Booth
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module top_win_4x8 #(
    parameter bit IS_PIPELINED = 1,
    parameter int MULT_TYPE    = 0,

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

    localparam int NUM_LANES    = 8;
    localparam int PP_PER_MUL   = MULT_TYPE == 0 ? ((IN_WIDTH_B + 2) + 1) / 2 : ((IN_WIDTH_B + 2) + 2) / 3;
    localparam int PP_SIZE      = 2 * PP_PER_MUL * NUM_LANES;
    localparam int CPR_IN_SIZE  = IN_SIZE / NUM_LANES / 2;
    localparam int CPR_IN_WIDTH = MULT_TYPE == 0 ? (IN_WIDTH_B + 2) + 2 : (IN_WIDTH_B + 2) + 3;
    localparam int PP_SHIFT     = MULT_TYPE == 0 ? 2 : 3;
    localparam int PP_WIDTH     = CPR_IN_WIDTH + $clog2(CPR_IN_SIZE) + 1 + ((PP_PER_MUL - 1) * PP_SHIFT);

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
    win_4x8 #(
        .MULT_TYPE(MULT_TYPE)
    ) win_4x8_i (
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
