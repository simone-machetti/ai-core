// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Processing Element core. A self-contained PE fed by the shared, already-
//   dispatched operands (a_dp8/b_dp8 from disp_array_a/disp_array_b) and the
//   broadcast control from ctrl. Chains: operand isolation -> pe_array ->
//   acc_array, plus the two acc pipeline registers.
//
//   Operand isolation: en_i AND-masks both dispatched operands to zero. The PE's
//   clock is gated externally by the same enable (one icg per PE), which freezes
//   pe_array/acc_array; the mask keeps the pe_array multipliers - which sit before
//   the first PE register (pe_array L0) and are fed by the still-toggling shared
//   dispatch - quiet while gated. Masking A alone zeros every partial product;
//   both are masked for a fully-quiet DP8.
//
//   Pipeline: the datapath is 3 stages (disp_array_a/b input reg, pe_array L0 reg,
//   acc_array output reg). acc_i is the per-PE external accumulator word; it is
//   pipelined by two registers here to meet the tap at the acc stage. sel_acc,
//   sel_out and prop_carry arrive already delayed to the right cycle (sel_acc is
//   pipelined once, shared, in the grid; sel_out/prop_carry in ctrl).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe #(
    localparam int NUM_DP8      = 16,
    localparam int A_DP8_WIDTH  = 64,
    localparam int B_DP8_WIDTH  = 32,
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
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [A_DP8_WIDTH-1:0] a_dp8_i       [ 0:NUM_DP8-1],
    input  logic [B_DP8_WIDTH-1:0] b_dp8_i       [ 0:NUM_DP8-1],
    input  logic                   en_i,
    input  logic [  NUM_LEVEL-1:0] en_level_i,
    input  logic                   is_signed_a_i [ 0:NUM_DP8-1],
    input  logic                   is_signed_b_i [ 0:NUM_DP8-1],
    input  logic [  NUM_SHIFT-1:0] sel_shift_i,
    input  logic [   PE_WIDTH-1:0] acc_i         [0:NUM_LANE-1],
    input  logic [  SEL_WIDTH-1:0] sel_out_i,
    input  logic                   sel_acc_i,
    input  logic                   prop_carry_i,
    output logic [   PE_WIDTH-1:0] out_o         [0:NUM_LANE-1]
);

    logic [A_DP8_WIDTH-1:0] a_dp8_m [0:NUM_DP8-1];
    logic [B_DP8_WIDTH-1:0] b_dp8_m [0:NUM_DP8-1];

    genvar d;
    generate
        for (d = 0; d < NUM_DP8; d++) begin : gen_mask
            assign a_dp8_m[d] = a_dp8_i[d] & {A_DP8_WIDTH{en_i}};
            assign b_dp8_m[d] = b_dp8_i[d] & {B_DP8_WIDTH{en_i}};
        end
    endgenerate

    logic [PE_WIDTH-1:0] acc_q1 [0:NUM_LANE-1];
    logic [PE_WIDTH-1:0] acc_q2 [0:NUM_LANE-1];

    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc1_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_i),  .q_o(acc_q1)
    );
    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc2_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_q1), .q_o(acc_q2)
    );

    logic [L0_TAP_WIDTH-1:0] l0_sum   [0:NUM_L0-1];
    logic [L0_TAP_WIDTH-1:0] l0_carry [0:NUM_L0-1];
    logic [L1_TAP_WIDTH-1:0] l1_sum   [0:NUM_L1-1];
    logic [L1_TAP_WIDTH-1:0] l1_carry [0:NUM_L1-1];
    logic [L2_TAP_WIDTH-1:0] l2_sum   [0:NUM_L2-1];
    logic [L2_TAP_WIDTH-1:0] l2_carry [0:NUM_L2-1];
    logic [L3_TAP_WIDTH-1:0] l3_sum;
    logic [L3_TAP_WIDTH-1:0] l3_carry;

    pe_array pe_array_i (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .a_dp8_i      (a_dp8_m),
        .b_dp8_i      (b_dp8_m),
        .is_signed_a_i(is_signed_a_i),
        .is_signed_b_i(is_signed_b_i),
        .sel_shift_i  (sel_shift_i),
        .en_level_i   (en_level_i),
        .l0_sum_o     (l0_sum),
        .l0_carry_o   (l0_carry),
        .l1_sum_o     (l1_sum),
        .l1_carry_o   (l1_carry),
        .l2_sum_o     (l2_sum),
        .l2_carry_o   (l2_carry),
        .l3_sum_o     (l3_sum),
        .l3_carry_o   (l3_carry)
    );

    acc_array acc_array_i (
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
        .acc_i       (acc_q2),
        .sel_out_i   (sel_out_i),
        .sel_acc_i   (sel_acc_i),
        .prop_carry_i(prop_carry_i),
        .pe_out_o    (out_o)
    );

endmodule
