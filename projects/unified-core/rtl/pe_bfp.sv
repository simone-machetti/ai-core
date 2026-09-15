// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   BFP Processing Element core - the pe variant carrying the exponent sideband.
//   Same shape as pe (operand isolation -> pe_array_bfp -> acc_array_bfp, plus the
//   acc pipeline registers), with the exponent path added exactly parallel to the
//   mantissa path:
//     - Operand isolation: en_i AND-masks the dispatched mantissa operands
//       (a_dp8/b_dp8) AND the dispatched exponent operands (exp_a_dp8/exp_b_dp8)
//       to zero. As in pe, the PE clock is gated externally by the same enable, so
//       the mask keeps the pe_array_bfp logic before the first PE register (the
//       still-toggling shared dispatch feeds the multipliers and the exponent
//       add/subtract) quiet while gated. Zeroed exponents are the minimum scale,
//       so a masked DP8 never wins an alignment max.
//     - acc pipeline: acc_i is delayed by two registers to meet the tap at the acc
//       stage (as in pe); acc_exp_i is delayed by the twin two registers so the
//       seed scale meets the tap scale at the accumulator.
//   The exponent seed / feedback share the mantissa format (20-bit lane word,
//   40-bit split H/L over a lane pair, plus a 7-bit product-domain scale); the
//   raw accumulator mantissa and scale leave un-normalized on out_o / pe_exp_o.
//
//   Pipeline: 3 stages (disp input reg upstream, pe_array_bfp L0 reg, acc_array_bfp
//   output reg). acc_i/acc_exp_i are per-PE; they are not masked (only the shared
//   dispatch is). sel_acc, sel_out and prop_carry arrive already delayed.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_bfp #(
    localparam int NUM_DP8      = 16,
    localparam int A_DP8_WIDTH  = 64,
    localparam int B_DP8_WIDTH  = 32,
    localparam int EXP_IN_WIDTH = 6,
    localparam int EXP_WIDTH    = 7,
    localparam int NUM_LEVEL    = 3,
    localparam int NUM_SHIFT    = 3,
    localparam int SEL_WIDTH    = 2,
    localparam int NUM_LANE     = 8,
    localparam int PE_WIDTH     = 20,
    localparam int NUM_L0       = 8,
    localparam int NUM_L1       = 4,
    localparam int NUM_L2       = 2,
    localparam int L0_TAP_WIDTH = 18,
    localparam int L1_TAP_WIDTH = 29,
    localparam int L2_TAP_WIDTH = 37,
    localparam int L3_TAP_WIDTH = 38
)(
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic [ A_DP8_WIDTH-1:0] a_dp8_i       [ 0:NUM_DP8-1],
    input  logic [ B_DP8_WIDTH-1:0] b_dp8_i       [ 0:NUM_DP8-1],
    input  logic [EXP_IN_WIDTH-1:0] exp_a_dp8_i   [ 0:NUM_DP8-1],
    input  logic [EXP_IN_WIDTH-1:0] exp_b_dp8_i   [ 0:NUM_DP8-1],
    input  logic                    en_i,
    input  logic [   NUM_LEVEL-1:0] en_level_i,
    input  logic                    is_signed_a_i [ 0:NUM_DP8-1],
    input  logic                    is_signed_b_i [ 0:NUM_DP8-1],
    input  logic [   NUM_SHIFT-1:0] sel_shift_i,
    input  logic [    PE_WIDTH-1:0] acc_i         [0:NUM_LANE-1],
    input  logic [   EXP_WIDTH-1:0] acc_exp_i     [0:NUM_LANE-1],
    input  logic [   SEL_WIDTH-1:0] sel_out_i,
    input  logic                    sel_acc_i,
    input  logic                    prop_carry_i,
    output logic [    PE_WIDTH-1:0] out_o         [0:NUM_LANE-1],
    output logic [   EXP_WIDTH-1:0] out_exp_o     [0:NUM_LANE-1]
);

    logic [ A_DP8_WIDTH-1:0] a_dp8_m     [0:NUM_DP8-1];
    logic [ B_DP8_WIDTH-1:0] b_dp8_m     [0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0] exp_a_dp8_m [0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0] exp_b_dp8_m [0:NUM_DP8-1];

    genvar d;
    generate
        for (d = 0; d < NUM_DP8; d++) begin : gen_mask
            assign a_dp8_m[d]     = a_dp8_i[d]     & {A_DP8_WIDTH{en_i}};
            assign b_dp8_m[d]     = b_dp8_i[d]     & {B_DP8_WIDTH{en_i}};
            assign exp_a_dp8_m[d] = exp_a_dp8_i[d] & {EXP_IN_WIDTH{en_i}};
            assign exp_b_dp8_m[d] = exp_b_dp8_i[d] & {EXP_IN_WIDTH{en_i}};
        end
    endgenerate

    logic [ PE_WIDTH-1:0] acc_q1     [0:NUM_LANE-1];
    logic [ PE_WIDTH-1:0] acc_q2     [0:NUM_LANE-1];
    logic [EXP_WIDTH-1:0] acc_exp_q1 [0:NUM_LANE-1];
    logic [EXP_WIDTH-1:0] acc_exp_q2 [0:NUM_LANE-1];

    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc1_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_i),  .q_o(acc_q1)
    );
    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc2_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_q1), .q_o(acc_q2)
    );
    reg_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_LANE)) reg_accexp1_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_exp_i),  .q_o(acc_exp_q1)
    );
    reg_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_LANE)) reg_accexp2_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_exp_q1), .q_o(acc_exp_q2)
    );

    logic [L0_TAP_WIDTH-1:0] l0_sum   [0:NUM_L0-1];
    logic [L0_TAP_WIDTH-1:0] l0_carry [0:NUM_L0-1];
    logic [   EXP_WIDTH-1:0] l0_exp   [0:NUM_L0-1];
    logic [L1_TAP_WIDTH-1:0] l1_sum   [0:NUM_L1-1];
    logic [L1_TAP_WIDTH-1:0] l1_carry [0:NUM_L1-1];
    logic [   EXP_WIDTH-1:0] l1_exp   [0:NUM_L1-1];
    logic [L2_TAP_WIDTH-1:0] l2_sum   [0:NUM_L2-1];
    logic [L2_TAP_WIDTH-1:0] l2_carry [0:NUM_L2-1];
    logic [   EXP_WIDTH-1:0] l2_exp   [0:NUM_L2-1];
    logic [L3_TAP_WIDTH-1:0] l3_sum;
    logic [L3_TAP_WIDTH-1:0] l3_carry;
    logic [   EXP_WIDTH-1:0] l3_exp;

    pe_array_bfp pe_array_bfp_i (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .a_dp8_i      (a_dp8_m),
        .b_dp8_i      (b_dp8_m),
        .is_signed_a_i(is_signed_a_i),
        .is_signed_b_i(is_signed_b_i),
        .exp_a_dp8_i  (exp_a_dp8_m),
        .exp_b_dp8_i  (exp_b_dp8_m),
        .sel_shift_i  (sel_shift_i),
        .en_level_i   (en_level_i),
        .l0_sum_o     (l0_sum),
        .l0_carry_o   (l0_carry),
        .l0_exp_o     (l0_exp),
        .l1_sum_o     (l1_sum),
        .l1_carry_o   (l1_carry),
        .l1_exp_o     (l1_exp),
        .l2_sum_o     (l2_sum),
        .l2_carry_o   (l2_carry),
        .l2_exp_o     (l2_exp),
        .l3_sum_o     (l3_sum),
        .l3_carry_o   (l3_carry),
        .l3_exp_o     (l3_exp)
    );

    acc_array_bfp acc_array_bfp_i (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .l0_sum_i    (l0_sum),
        .l0_carry_i  (l0_carry),
        .l1_sum_i    (l1_sum),
        .l1_carry_i  (l1_carry),
        .l2_sum_i    (l2_sum),
        .l2_carry_i  (l2_carry),
        .l3_sum_i    (l3_sum),
        .l3_carry_i  (l3_carry),
        .l0_exp_i    (l0_exp),
        .l1_exp_i    (l1_exp),
        .l2_exp_i    (l2_exp),
        .l3_exp_i    (l3_exp),
        .acc_i       (acc_q2),
        .acc_exp_i   (acc_exp_q2),
        .sel_out_i   (sel_out_i),
        .sel_acc_i   (sel_acc_i),
        .prop_carry_i(prop_carry_i),
        .pe_out_o    (out_o),
        .pe_exp_o    (out_exp_o)
    );

endmodule
