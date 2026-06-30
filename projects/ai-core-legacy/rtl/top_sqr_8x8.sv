// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Top-level Processing Element: Squaring 8-bit × 8-bit multiply-accumulate
//   array with 32 lanes and 3 accumulators.
//
//   Pipeline (IS_PIPELINED = 1, 3-cycle latency):
//     Cycle 1: ff_n registers a_i and b_i.
//     Cycle 2: add_sqr_s_9_bit_array generates partial products; cpr_tree_8x8
//              stage 0 compresses and registers intermediate results.
//     Cycle 3: cpr_tree_8x8 completes; ff registers the 48-bit result.
//
//   Function: out = sum_i((a[i]+b[i])^2) + acc[0] + acc[1] + acc[2]
//
// Parameters:
//   IS_PIPELINED - 1 = 3-cycle latency; 0 = 2-cycle (no cpr_tree register)
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module top_sqr_8x8 #(
    parameter bit IS_PIPELINED = 1,

    localparam int IN_SIZE    = 32,
    localparam int IN_WIDTH_A = 8,
    localparam int IN_WIDTH_B = 8,
    localparam int ACC_SIZE   = 3,
    localparam int ACC_WIDTH  = 48,
    localparam int EXT_NUM    = 7,
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

    localparam int PP_SIZE  = IN_SIZE;
    localparam int PP_WIDTH = (IN_WIDTH_A + 1) * 2;
    localparam int EXT_BITS = 4;

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
    add_sqr_s_9_bit_array #(
        .IN_SIZE(IN_SIZE)
    ) add_sqr_s_9_bit_array_i (
        .a_i (a),
        .b_i (b),
        .pp_o(pp)
    );

    // -------------------------------------------------------------------------
    // Compression tree
    // -------------------------------------------------------------------------
    cpr_tree_8x8 #(
        .IS_PIPELINED(IS_PIPELINED),
        .PP_SIZE     (PP_SIZE),
        .PP_WIDTH    (PP_WIDTH),
        .EXT_BITS    (EXT_BITS),
        .ACC_SIZE    (ACC_SIZE)
    ) cpr_tree_8x8_i (
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
