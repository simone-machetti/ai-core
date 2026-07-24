// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Dummy top-level used as a fast vehicle to exercise the complete EDA flow
//   (simulation, synthesis, place-and-route and every post-synthesis /
//   post-place-and-route analysis). Wraps a single dp_8 dot-product core with
//   reg_n input registers (operands and signedness flags) and reg_n output
//   registers (carry-save result), so the design is one clean reg-to-reg
//   pipeline stage through the real Booth + compressor datapath. Latency is
//   2 cycles: inputs are captured on the first rising edge, the registered
//   carry-save result appears after the second. Not part of the AI-Core
//   architecture - flow validation only.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module top_dummy #(
    localparam int LANES      = 8,
    localparam int IN_WIDTH_A = 8,
    localparam int IN_WIDTH_B = 4,
    localparam int PP_SIZE    = IN_WIDTH_B / 2 + 1,
    localparam int PP_WIDTH   = IN_WIDTH_A + 2,
    localparam int CPR2_WIDTH = PP_WIDTH + $clog2(LANES) + 1,
    localparam int FINAL_IN   = CPR2_WIDTH + 2 * (PP_SIZE - 1),
    localparam int FINAL_EXT  = 2,
    localparam int OUT_WIDTH  = FINAL_IN + FINAL_EXT
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic [IN_WIDTH_A-1:0] a_i [0:LANES-1],
    input  logic [IN_WIDTH_B-1:0] b_i [0:LANES-1],
    input  logic                  is_signed_a_i,
    input  logic                  is_signed_b_i,
    output logic [ OUT_WIDTH-1:0] sum_o,
    output logic [ OUT_WIDTH-1:0] carry_o
);

    logic [IN_WIDTH_A-1:0] a_q   [0:LANES-1];
    logic [IN_WIDTH_B-1:0] b_q   [0:LANES-1];
    logic                  sgn_d [      0:1];
    logic                  sgn_q [      0:1];
    logic [ OUT_WIDTH-1:0] out_d [      0:1];
    logic [ OUT_WIDTH-1:0] out_q [      0:1];

    reg_n #(.WIDTH(IN_WIDTH_A), .SIZE(LANES)) reg_a_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(a_i), .q_o(a_q)
    );

    reg_n #(.WIDTH(IN_WIDTH_B), .SIZE(LANES)) reg_b_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(b_i), .q_o(b_q)
    );

    assign sgn_d[0] = is_signed_a_i;
    assign sgn_d[1] = is_signed_b_i;

    reg_n #(.WIDTH(1), .SIZE(2)) reg_sgn_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(sgn_d), .q_o(sgn_q)
    );

    dp_8 dp_8_i (
        .a_i          (a_q),
        .b_i          (b_q),
        .is_signed_a_i(sgn_q[0]),
        .is_signed_b_i(sgn_q[1]),
        .sum_o        (out_d[0]),
        .carry_o      (out_d[1])
    );

    reg_n #(.WIDTH(OUT_WIDTH), .SIZE(2)) reg_out_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(out_d), .q_o(out_q)
    );

    assign sum_o   = out_q[0];
    assign carry_o = out_q[1];

endmodule
