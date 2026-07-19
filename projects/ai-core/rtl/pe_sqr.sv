// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Processing Element core, square variant. Like pe.sv it is fed the shared,
//   already-dispatched operands and the broadcast control, and chains
//   pe_array_sqr -> acc_array_sqr plus the two acc pipeline registers. The
//   difference from the multiply PE: the alpha/beta corrections are computed by
//   the row/column generators outside, so their carry-save taps arrive here as
//   inputs (pre-aligned - the generators share the row/column dispatch and have
//   the same depth as pe_array_sqr) and the per-mode constant comes from the
//   shared const_sqr. This module holds only pe_array_sqr, acc_array_sqr and the
//   two acc registers; everything shared (dispatch, ctrl, const, alpha/beta
//   generators) lives in the grid.
//
//   Operand isolation: en_i AND-masks every per-cycle datapath input - both
//   dispatched operands and the -alpha/-beta tap buses - to zero. The PE clock is
//   gated externally by the same enable (one icg per PE), which freezes the
//   registers; the mask keeps the pe_array_sqr squarers and the acc_array_sqr
//   combinational logic - fed by the still-toggling shared dispatch/generators -
//   quiet while gated. C/c_neg (mode-constant) and acc (clock-gated regs) hold on
//   their own, so they need no mask.
//
//   Pipeline: identical depth to pe.sv - one pe_array_sqr L0 register and one
//   acc_array_sqr output register inside (the disp input register is outside).
//   acc_i is pipelined by two registers here to meet the tap at the acc stage;
//   the -alpha/-beta taps, C and the acc-stage selects arrive already aligned
//   from the shared generators / const / ctrl.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_sqr #(
    localparam int NUM_DP8     = 16,
    localparam int A_DP8_WIDTH = 64,
    localparam int B_DP8_WIDTH = 32,
    localparam int NUM_SHIFT   = 3,
    localparam int NUM_NEG     = 6,
    localparam int SEL_WIDTH   = 2,
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
    input  logic [A_DP8_WIDTH-1:0] a_dp8_i      [0:NUM_DP8-1],
    input  logic [B_DP8_WIDTH-1:0] b_dp8_i      [0:NUM_DP8-1],
    input  logic                   en_i,
    input  logic [    NUM_NEG-1:0] neg_i,
    input  logic [  NUM_SHIFT-1:0] sel_shift_i,

    input  logic [     L0_TAP-1:0] a_l0_sum_i   [0:NUM_L0-1],
    input  logic [     L0_TAP-1:0] a_l0_carry_i [0:NUM_L0-1],
    input  logic [     L1_TAP-1:0] a_l1_sum_i   [0:NUM_L1-1],
    input  logic [     L1_TAP-1:0] a_l1_carry_i [0:NUM_L1-1],
    input  logic [     L2_TAP-1:0] a_l2_sum_i   [0:NUM_L2-1],
    input  logic [     L2_TAP-1:0] a_l2_carry_i [0:NUM_L2-1],
    input  logic [     L3_TAP-1:0] a_l3_sum_i,
    input  logic [     L3_TAP-1:0] a_l3_carry_i,

    input  logic [     L0_TAP-1:0] b_l0_sum_i   [0:NUM_L0-1],
    input  logic [     L0_TAP-1:0] b_l0_carry_i [0:NUM_L0-1],
    input  logic [     L1_TAP-1:0] b_l1_sum_i   [0:NUM_L1-1],
    input  logic [     L1_TAP-1:0] b_l1_carry_i [0:NUM_L1-1],
    input  logic [     L2_TAP-1:0] b_l2_sum_i   [0:NUM_L2-1],
    input  logic [     L2_TAP-1:0] b_l2_carry_i [0:NUM_L2-1],
    input  logic [     L3_TAP-1:0] b_l3_sum_i,
    input  logic [     L3_TAP-1:0] b_l3_carry_i,

    input  logic [    C_WIDTH-1:0] c_i,
    input  logic [ CNEG_WIDTH-1:0] c_neg_i,
    input  logic [   PE_WIDTH-1:0] acc_i        [0:NUM_LANE-1],
    input  logic [  SEL_WIDTH-1:0] sel_out_i,
    input  logic                   sel_acc_i,
    input  logic [  SEL_WIDTH-1:0] sel_const_i,
    input  logic                   prop_carry_i,
    output logic [   PE_WIDTH-1:0] out_o        [0:NUM_LANE-1]
);

    logic [A_DP8_WIDTH-1:0] a_dp8_m    [0:NUM_DP8-1];
    logic [B_DP8_WIDTH-1:0] b_dp8_m    [0:NUM_DP8-1];
    logic [     L0_TAP-1:0] a_l0_sum_m [ 0:NUM_L0-1], a_l0_carry_m [0:NUM_L0-1];
    logic [     L1_TAP-1:0] a_l1_sum_m [ 0:NUM_L1-1], a_l1_carry_m [0:NUM_L1-1];
    logic [     L2_TAP-1:0] a_l2_sum_m [ 0:NUM_L2-1], a_l2_carry_m [0:NUM_L2-1];
    logic [     L3_TAP-1:0] a_l3_sum_m, a_l3_carry_m;
    logic [     L0_TAP-1:0] b_l0_sum_m [ 0:NUM_L0-1], b_l0_carry_m [0:NUM_L0-1];
    logic [     L1_TAP-1:0] b_l1_sum_m [ 0:NUM_L1-1], b_l1_carry_m [0:NUM_L1-1];
    logic [     L2_TAP-1:0] b_l2_sum_m [ 0:NUM_L2-1], b_l2_carry_m [0:NUM_L2-1];
    logic [     L3_TAP-1:0] b_l3_sum_m, b_l3_carry_m;

    genvar d;
    generate
        for (d = 0; d < NUM_DP8; d++) begin : gen_mask_dp8
            assign a_dp8_m[d] = a_dp8_i[d] & {A_DP8_WIDTH{en_i}};
            assign b_dp8_m[d] = b_dp8_i[d] & {B_DP8_WIDTH{en_i}};
        end
        for (d = 0; d < NUM_L0; d++) begin : gen_mask_l0
            assign a_l0_sum_m[d]   = a_l0_sum_i[d]   & {L0_TAP{en_i}};
            assign a_l0_carry_m[d] = a_l0_carry_i[d] & {L0_TAP{en_i}};
            assign b_l0_sum_m[d]   = b_l0_sum_i[d]   & {L0_TAP{en_i}};
            assign b_l0_carry_m[d] = b_l0_carry_i[d] & {L0_TAP{en_i}};
        end
        for (d = 0; d < NUM_L1; d++) begin : gen_mask_l1
            assign a_l1_sum_m[d]   = a_l1_sum_i[d]   & {L1_TAP{en_i}};
            assign a_l1_carry_m[d] = a_l1_carry_i[d] & {L1_TAP{en_i}};
            assign b_l1_sum_m[d]   = b_l1_sum_i[d]   & {L1_TAP{en_i}};
            assign b_l1_carry_m[d] = b_l1_carry_i[d] & {L1_TAP{en_i}};
        end
        for (d = 0; d < NUM_L2; d++) begin : gen_mask_l2
            assign a_l2_sum_m[d]   = a_l2_sum_i[d]   & {L2_TAP{en_i}};
            assign a_l2_carry_m[d] = a_l2_carry_i[d] & {L2_TAP{en_i}};
            assign b_l2_sum_m[d]   = b_l2_sum_i[d]   & {L2_TAP{en_i}};
            assign b_l2_carry_m[d] = b_l2_carry_i[d] & {L2_TAP{en_i}};
        end
    endgenerate
    assign a_l3_sum_m   = a_l3_sum_i   & {L3_TAP{en_i}};
    assign a_l3_carry_m = a_l3_carry_i & {L3_TAP{en_i}};
    assign b_l3_sum_m   = b_l3_sum_i   & {L3_TAP{en_i}};
    assign b_l3_carry_m = b_l3_carry_i & {L3_TAP{en_i}};

    logic [PE_WIDTH-1:0] acc_q1 [0:NUM_LANE-1];
    logic [PE_WIDTH-1:0] acc_q2 [0:NUM_LANE-1];

    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc1_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_i),  .q_o(acc_q1)
    );
    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc2_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_q1), .q_o(acc_q2)
    );

    logic [L0_TAP-1:0] pe_l0_sum [0:NUM_L0-1], pe_l0_carry [0:NUM_L0-1];
    logic [L1_TAP-1:0] pe_l1_sum [0:NUM_L1-1], pe_l1_carry [0:NUM_L1-1];
    logic [L2_TAP-1:0] pe_l2_sum [0:NUM_L2-1], pe_l2_carry [0:NUM_L2-1];
    logic [L3_TAP-1:0] pe_l3_sum, pe_l3_carry;

    pe_array_sqr pe_array_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .a_dp8_i(a_dp8_m), .b_dp8_i(b_dp8_m),
        .neg_i(neg_i), .sel_shift_i(sel_shift_i),
        .l0_sum_o(pe_l0_sum), .l0_carry_o(pe_l0_carry),
        .l1_sum_o(pe_l1_sum), .l1_carry_o(pe_l1_carry),
        .l2_sum_o(pe_l2_sum), .l2_carry_o(pe_l2_carry),
        .l3_sum_o(pe_l3_sum), .l3_carry_o(pe_l3_carry)
    );

    acc_array_sqr acc_array_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .pe_l0_sum_i(pe_l0_sum), .pe_l0_carry_i(pe_l0_carry),
        .pe_l1_sum_i(pe_l1_sum), .pe_l1_carry_i(pe_l1_carry),
        .pe_l2_sum_i(pe_l2_sum), .pe_l2_carry_i(pe_l2_carry),
        .pe_l3_sum_i(pe_l3_sum), .pe_l3_carry_i(pe_l3_carry),
        .a_l0_sum_i(a_l0_sum_m), .a_l0_carry_i(a_l0_carry_m),
        .a_l1_sum_i(a_l1_sum_m), .a_l1_carry_i(a_l1_carry_m),
        .a_l2_sum_i(a_l2_sum_m), .a_l2_carry_i(a_l2_carry_m),
        .a_l3_sum_i(a_l3_sum_m), .a_l3_carry_i(a_l3_carry_m),
        .b_l0_sum_i(b_l0_sum_m), .b_l0_carry_i(b_l0_carry_m),
        .b_l1_sum_i(b_l1_sum_m), .b_l1_carry_i(b_l1_carry_m),
        .b_l2_sum_i(b_l2_sum_m), .b_l2_carry_i(b_l2_carry_m),
        .b_l3_sum_i(b_l3_sum_m), .b_l3_carry_i(b_l3_carry_m),
        .c_i(c_i), .c_neg_i(c_neg_i),
        .acc_i(acc_q2),
        .sel_out_i(sel_out_i), .sel_acc_i(sel_acc_i),
        .sel_const_i(sel_const_i), .prop_carry_i(prop_carry_i),
        .pe_out_o(out_o)
    );

endmodule
