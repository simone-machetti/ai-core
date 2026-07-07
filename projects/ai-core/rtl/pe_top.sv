// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Top level of one Processing Element (PE). Wires the combinational mode
//   decoder pe_ctrl to pe_datapath (disp_array -> pe_array -> acc_array) and
//   adds the control-path pipeline registers that align each control with the
//   data it meets.
//
//   The datapath is a 3-stage pipeline (disp input reg, pe_array L0 reg, acc
//   output reg), all inside pe_datapath. mode_i, sel_acc_i and acc_i arrive
//   together at the top and are registered once on input; pe_ctrl then decodes
//   the registered mode. The decoded disp selects / gates, the per-DP8
//   signedness and the L0 shift are used in the first datapath stage and go
//   straight through; the L1/L2 shifts and the acc controls (sel_out,
//   prop_carry) are used in the second stage and pass through one more
//   register. sel_acc and acc are delayed one more cycle the same way, to reach
//   the acc stage. sel_shift is reassembled with its low bit (L0) combinational
//   and its high bits (L1/L2) registered.
//
//   Latency: pe_out_o is valid 3 clocks after the operands and mode are applied.
//   sel_acc selects, per lane, fresh output (0, folds acc_i) or accumulation
//   onto the running register (1); acc_i is the external accumulator word.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_top #(
    localparam int NUM_BLK     = 4,
    localparam int BLK_WIDTH   = 64,
    localparam int PE_IN_WIDTH = NUM_BLK * BLK_WIDTH,
    localparam int NUM_PAIR    = 8,
    localparam int NUM_DP8     = 16,
    localparam int SEL_WIDTH   = 2,
    localparam int OP_WIDTH    = 2,
    localparam int NUM_SHIFT   = 3,
    localparam int SHIFT_HI    = 2,
    localparam int NUM_LANE    = 8,
    localparam int PE_WIDTH    = 20,
    localparam int MODE_WIDTH  = 4
)(
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [PE_IN_WIDTH-1:0] pe_in_a_i,
    input  logic [PE_IN_WIDTH-1:0] pe_in_b_i,
    input  logic [ MODE_WIDTH-1:0] mode_i,
    input  logic                   sel_acc_i,
    input  logic [   PE_WIDTH-1:0] acc_i    [0:NUM_LANE-1],
    output logic [   PE_WIDTH-1:0] pe_out_o [0:NUM_LANE-1]
);

    logic [MODE_WIDTH-1:0] mode_d    [0:0];
    logic [MODE_WIDTH-1:0] mode_q1   [0:0];
    logic                  selacc_d  [0:0];
    logic                  selacc_q1 [0:0];
    logic [  PE_WIDTH-1:0] acc_q1    [0:NUM_LANE-1];

    assign mode_d[0]   = mode_i;
    assign selacc_d[0] = sel_acc_i;

    reg_n #(.WIDTH(MODE_WIDTH), .SIZE(1)) reg_mode_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(mode_d), .q_o(mode_q1)
    );
    reg_n #(.WIDTH(1), .SIZE(1)) reg_selacc1_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selacc_d), .q_o(selacc_q1)
    );
    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc1_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_i), .q_o(acc_q1)
    );

    logic [SEL_WIDTH-1:0] sel_a_ctrl       [0:NUM_PAIR-1];
    logic [SEL_WIDTH-1:0] sel_b_ctrl       [0:NUM_PAIR-1];
    logic [ OP_WIDTH-1:0] ctr_l_ctrl       [0:NUM_PAIR-1];
    logic [ OP_WIDTH-1:0] ctr_h_ctrl       [0:NUM_PAIR-1];
    logic                 is_signed_a_ctrl [0:NUM_DP8-1];
    logic                 is_signed_b_ctrl [0:NUM_DP8-1];
    logic [NUM_SHIFT-1:0] sel_shift_ctrl;
    logic [SEL_WIDTH-1:0] sel_out_ctrl;
    logic                 prop_carry_ctrl;

    pe_ctrl pe_ctrl_i (
        .mode_i       (mode_q1[0]),
        .sel_a_o      (sel_a_ctrl),
        .sel_b_o      (sel_b_ctrl),
        .ctr_l_o      (ctr_l_ctrl),
        .ctr_h_o      (ctr_h_ctrl),
        .is_signed_a_o(is_signed_a_ctrl),
        .is_signed_b_o(is_signed_b_ctrl),
        .sel_shift_o  (sel_shift_ctrl),
        .sel_out_o    (sel_out_ctrl),
        .prop_carry_o (prop_carry_ctrl)
    );

    logic [ SHIFT_HI-1:0] shifthi_d [0:0];
    logic [ SHIFT_HI-1:0] shifthi_q [0:0];
    logic [SEL_WIDTH-1:0] selout_d  [0:0];
    logic [SEL_WIDTH-1:0] selout_q  [0:0];
    logic                 propc_d   [0:0];
    logic                 propc_q   [0:0];

    assign shifthi_d[0] = sel_shift_ctrl[NUM_SHIFT-1:1];
    assign selout_d[0]  = sel_out_ctrl;
    assign propc_d[0]   = prop_carry_ctrl;

    reg_n #(.WIDTH(SHIFT_HI), .SIZE(1)) reg_shifthi_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(shifthi_d), .q_o(shifthi_q)
    );
    reg_n #(.WIDTH(SEL_WIDTH), .SIZE(1)) reg_selout_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selout_d), .q_o(selout_q)
    );
    reg_n #(.WIDTH(1), .SIZE(1)) reg_propc_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(propc_d), .q_o(propc_q)
    );

    logic                  selacc_q2 [0:0];
    logic [  PE_WIDTH-1:0] acc_q2    [0:NUM_LANE-1];

    reg_n #(.WIDTH(1), .SIZE(1)) reg_selacc2_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selacc_q1), .q_o(selacc_q2)
    );
    reg_n #(.WIDTH(PE_WIDTH), .SIZE(NUM_LANE)) reg_acc2_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(acc_q1), .q_o(acc_q2)
    );

    logic [NUM_SHIFT-1:0] sel_shift_dp;
    assign sel_shift_dp = {shifthi_q[0], sel_shift_ctrl[0]};

    pe_datapath pe_datapath_i (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .pe_in_a_i    (pe_in_a_i),
        .pe_in_b_i    (pe_in_b_i),
        .sel_a_i      (sel_a_ctrl),
        .sel_b_i      (sel_b_ctrl),
        .ctr_l_i      (ctr_l_ctrl),
        .ctr_h_i      (ctr_h_ctrl),
        .is_signed_a_i(is_signed_a_ctrl),
        .is_signed_b_i(is_signed_b_ctrl),
        .sel_shift_i  (sel_shift_dp),
        .acc_i        (acc_q2),
        .sel_out_i    (selout_q[0]),
        .sel_acc_i    (selacc_q2[0]),
        .prop_carry_i (propc_q[0]),
        .pe_out_o     (pe_out_o)
    );

endmodule
