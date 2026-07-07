// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   PE datapath wrapper. Chains the three datapath stages of one Processing
//   Element - disp_array -> pe_array -> acc_array - and exposes their control
//   ports directly. The carry-save taps between pe_array and acc_array are
//   internal. Each stage keeps its own pipeline register (disp_array input,
//   pe_array L0, acc_array output), so the datapath is a 3-stage pipeline; the
//   control-side pipeline alignment that feeds these ports lives in pe_top.
//
//   The controls are consumed at different pipeline stages: the disp selects /
//   gates and the pe signedness / L0 shift act in the first stage, the pe L1/L2
//   shifts and all acc controls in the second stage. pe_top delivers each of
//   them already delayed to the right cycle; this wrapper only wires them.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_datapath #(
    localparam int NUM_BLK      = 4,
    localparam int BLK_WIDTH    = 64,
    localparam int NUM_PAIR     = 8,
    localparam int NUM_DP8      = 16,
    localparam int SEL_WIDTH    = 2,
    localparam int OP_WIDTH     = 2,
    localparam int A_DP8_WIDTH  = 64,
    localparam int B_DP8_WIDTH  = 32,
    localparam int NUM_SHIFT    = 3,
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
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_a_i,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b_i,
    input  logic [        SEL_WIDTH-1:0] sel_a_i       [0:NUM_PAIR-1],
    input  logic [        SEL_WIDTH-1:0] sel_b_i       [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_l_i       [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_h_i       [0:NUM_PAIR-1],
    input  logic                         is_signed_a_i [0:NUM_DP8-1],
    input  logic                         is_signed_b_i [0:NUM_DP8-1],
    input  logic [        NUM_SHIFT-1:0] sel_shift_i,
    input  logic [         PE_WIDTH-1:0] acc_i         [0:NUM_LANE-1],
    input  logic [        SEL_WIDTH-1:0] sel_out_i,
    input  logic                         sel_acc_i,
    input  logic                         prop_carry_i,
    output logic [         PE_WIDTH-1:0] pe_out_o      [0:NUM_LANE-1]
);

    logic [A_DP8_WIDTH-1:0]  a_dp8    [0:NUM_DP8-1];
    logic [B_DP8_WIDTH-1:0]  b_dp8    [0:NUM_DP8-1];

    logic [L0_TAP_WIDTH-1:0] l0_sum   [0:NUM_L0-1];
    logic [L0_TAP_WIDTH-1:0] l0_carry [0:NUM_L0-1];
    logic [L1_TAP_WIDTH-1:0] l1_sum   [0:NUM_L1-1];
    logic [L1_TAP_WIDTH-1:0] l1_carry [0:NUM_L1-1];
    logic [L2_TAP_WIDTH-1:0] l2_sum   [0:NUM_L2-1];
    logic [L2_TAP_WIDTH-1:0] l2_carry [0:NUM_L2-1];
    logic [L3_TAP_WIDTH-1:0] l3_sum;
    logic [L3_TAP_WIDTH-1:0] l3_carry;

    disp_array disp_array_i (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .pe_in_a_i(pe_in_a_i),
        .pe_in_b_i(pe_in_b_i),
        .sel_a_i  (sel_a_i),
        .sel_b_i  (sel_b_i),
        .ctr_l_i  (ctr_l_i),
        .ctr_h_i  (ctr_h_i),
        .a_dp8_o  (a_dp8),
        .b_dp8_o  (b_dp8)
    );

    pe_array pe_array_i (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .a_dp8_i      (a_dp8),
        .b_dp8_i      (b_dp8),
        .is_signed_a_i(is_signed_a_i),
        .is_signed_b_i(is_signed_b_i),
        .sel_shift_i  (sel_shift_i),
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
        .acc_i       (acc_i),
        .sel_out_i   (sel_out_i),
        .sel_acc_i   (sel_acc_i),
        .prop_carry_i(prop_carry_i),
        .pe_out_o    (pe_out_o)
    );

endmodule
