// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Shared mode decoder + control pipeline for the square PE grid, the ctrl.sv
//   analogue. One instance serves every PE, row dispatcher/alpha generator and
//   column dispatcher/beta generator. Maps the 4-bit mode_i to every square
//   control:
//     - disp_array_a_sqr : block selects sel_a, centering is_signed_a, idle zero
//     - disp_array_b_sqr : block selects sel_b, centering is_signed_b, idle zero
//     - pe_array_sqr / alpha / beta : complex block-negate neg, tree shift enables
//                      sel_shift; alpha uses is_signed_b, beta uses is_signed_a/zero
//     - acc_array_sqr   : tap select sel_out, const-mux pattern sel_const, lane-
//                      fusion carry enable prop_carry
//   It drops ctr_l/ctr_h (the square B dispatcher has no shift) and adds zero,
//   neg and sel_const. Like ctrl, mode_i is registered once (mode_q1) and the
//   decode is combinational from it: the first-stage controls (dispatch, signed,
//   idle-zero, block-negate, sel_shift[0]) go straight out; the second-stage
//   controls (sel_shift[2:1], sel_out, sel_const, prop_carry) pass through one
//   more register so each meets the data it belongs to. sel_acc and the constant
//   (const_sqr) are handled at the top level; sel_acc is pipelined there.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module ctrl_sqr #(
    localparam int NUM_PAIR   = 8,
    localparam int NUM_DP8    = 16,
    localparam int SEL_WIDTH  = 2,
    localparam int NUM_SHIFT  = 3,
    localparam int NUM_NEG    = 6,
    localparam int SHIFT_HI   = 2,
    localparam int MODE_WIDTH = 4,
    localparam int NUM_ENTRY  = 16
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic [MODE_WIDTH-1:0] mode_i,
    output logic [ SEL_WIDTH-1:0] sel_a_o       [0:NUM_PAIR-1],
    output logic [ SEL_WIDTH-1:0] sel_b_o       [0:NUM_PAIR-1],
    output logic                  is_signed_a_o [ 0:NUM_DP8-1],
    output logic                  is_signed_b_o [ 0:NUM_DP8-1],
    output logic                  zero_o        [ 0:NUM_DP8-1],
    output logic [   NUM_NEG-1:0] neg_o,
    output logic [ NUM_SHIFT-1:0] sel_shift_o,
    output logic [ SEL_WIDTH-1:0] sel_out_o,
    output logic [ SEL_WIDTH-1:0] sel_const_o,
    output logic                  prop_carry_o
);

    localparam logic [SEL_WIDTH-1:0] SEL_A_LUT [0:NUM_ENTRY-1][0:NUM_PAIR-1] = '{
        '{default: 2'd0},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{default: 2'd0},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd0, 2'd1, 2'd1},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0}
    };

    localparam logic [SEL_WIDTH-1:0] SEL_B_LUT [0:NUM_ENTRY-1][0:NUM_PAIR-1] = '{
        '{default: 2'd0},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd0, 2'd1, 2'd1},
        '{default: 2'd0},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd1, 2'd0, 2'd2, 2'd3, 2'd3, 2'd2},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd1, 2'd0, 2'd3, 2'd2},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0}
    };

    localparam logic IS_SIGNED_A_LUT [0:NUM_ENTRY-1][0:NUM_DP8-1] = '{
        '{default: 1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0},
        '{default: 1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0},
        '{1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0},
        '{1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0}
    };

    localparam logic IS_SIGNED_B_LUT [0:NUM_ENTRY-1][0:NUM_DP8-1] = '{
        '{default: 1'b0},
        '{default: 1'b1},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{default: 1'b0},
        '{default: 1'b1},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0},
        '{1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0}
    };

    localparam logic ZERO_LUT [0:NUM_ENTRY-1][0:NUM_DP8-1] = '{
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0}
    };

    localparam logic [NUM_NEG-1:0] NEG_LUT [0:NUM_ENTRY-1] = '{
        6'b000000, 6'b000000, 6'b000000, 6'b000000, 6'b000000, 6'b000000,
        6'b000000, 6'b000000, 6'b000000, 6'b000000, 6'b110011, 6'b001111,
        6'b000000, 6'b000000, 6'b000000, 6'b000000
    };

    localparam logic [NUM_SHIFT-1:0] SEL_SHIFT_LUT [0:NUM_ENTRY-1] = '{
        3'b000, 3'b000, 3'b010, 3'b011, 3'b000, 3'b000, 3'b010, 3'b011,
        3'b111, 3'b111, 3'b010, 3'b010, 3'b111, 3'b000, 3'b000, 3'b000
    };

    localparam logic [SEL_WIDTH-1:0] SEL_OUT_LUT [0:NUM_ENTRY-1] = '{
        2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd2, 2'd3, 2'd2,
        2'd3, 2'd2, 2'd1, 2'd2, 2'd2, 2'd0, 2'd0, 2'd0
    };

    localparam logic [SEL_WIDTH-1:0] SEL_CONST_LUT [0:NUM_ENTRY-1] = '{
        2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd1, 2'd1, 2'd1,
        2'd1, 2'd1, 2'd2, 2'd3, 2'd1, 2'd0, 2'd0, 2'd0
    };

    logic [MODE_WIDTH-1:0] mode_d  [0:0];
    logic [MODE_WIDTH-1:0] mode_q1 [0:0];

    assign mode_d[0] = mode_i;

    reg_n #(.WIDTH(MODE_WIDTH), .SIZE(1)) reg_mode_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(mode_d), .q_o(mode_q1)
    );

    logic [NUM_SHIFT-1:0] sel_shift_c;
    logic [SEL_WIDTH-1:0] sel_out_c;
    logic [SEL_WIDTH-1:0] sel_const_c;
    logic                 prop_carry_c;

    genvar p, i;
    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_disp
            assign sel_a_o[p] = SEL_A_LUT[mode_q1[0]][p];
            assign sel_b_o[p] = SEL_B_LUT[mode_q1[0]][p];
        end
        for (i = 0; i < NUM_DP8; i++) begin : gen_pe
            assign is_signed_a_o[i] = IS_SIGNED_A_LUT[mode_q1[0]][i];
            assign is_signed_b_o[i] = IS_SIGNED_B_LUT[mode_q1[0]][i];
            assign zero_o[i]        = ZERO_LUT[mode_q1[0]][i];
        end
    endgenerate

    assign neg_o        = NEG_LUT[mode_q1[0]];
    assign sel_shift_c  = SEL_SHIFT_LUT[mode_q1[0]];
    assign sel_out_c    = SEL_OUT_LUT[mode_q1[0]];
    assign sel_const_c  = SEL_CONST_LUT[mode_q1[0]];
    assign prop_carry_c = (SEL_OUT_LUT[mode_q1[0]] != '0);

    logic [ SHIFT_HI-1:0] shifthi_d  [0:0];
    logic [ SHIFT_HI-1:0] shifthi_q  [0:0];
    logic [SEL_WIDTH-1:0] selout_d   [0:0];
    logic [SEL_WIDTH-1:0] selout_q   [0:0];
    logic [SEL_WIDTH-1:0] selconst_d [0:0];
    logic [SEL_WIDTH-1:0] selconst_q [0:0];
    logic                 propc_d    [0:0];
    logic                 propc_q    [0:0];

    assign shifthi_d[0]  = sel_shift_c[NUM_SHIFT-1:1];
    assign selout_d[0]   = sel_out_c;
    assign selconst_d[0] = sel_const_c;
    assign propc_d[0]    = prop_carry_c;

    reg_n #(.WIDTH(SHIFT_HI), .SIZE(1)) reg_shifthi_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(shifthi_d), .q_o(shifthi_q)
    );
    reg_n #(.WIDTH(SEL_WIDTH), .SIZE(1)) reg_selout_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selout_d), .q_o(selout_q)
    );
    reg_n #(.WIDTH(SEL_WIDTH), .SIZE(1)) reg_selconst_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selconst_d), .q_o(selconst_q)
    );
    reg_n #(.WIDTH(1), .SIZE(1)) reg_propc_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(propc_d), .q_o(propc_q)
    );

    assign sel_shift_o  = {shifthi_q[0], sel_shift_c[0]};
    assign sel_out_o    = selout_q[0];
    assign sel_const_o  = selconst_q[0];
    assign prop_carry_o = propc_q[0];

endmodule
