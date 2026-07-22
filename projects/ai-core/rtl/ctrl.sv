// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Shared mode decoder + control pipeline for the PE grid. One instance serves
//   every PE (the mode is broadcast grid-wide), so the decode is not replicated
//   per PE. Maps the 4-bit mode_i to every internal control the datapath needs:
//     - disp_array_a : A block selects sel_a
//     - disp_array_b : B block selects sel_b and B-gate controls ctr_l/ctr_h
//     - pe           : per-DP8 signedness is_signed_a/is_signed_b, the tree shift
//                      enables sel_shift, the tap select sel_out and the lane-
//                      fusion carry enable prop_carry, and the tree operand-
//                      isolation enables en_level
//   Built as a lookup table indexed by the registered mode. mode_i is registered
//   once on input (mode_q1), and the decode is combinational from mode_q1: the
//   disp selects/gates, the signedness and the L0 shift (sel_shift[0]) act in the
//   first datapath stage and go straight out; the L1/L2 shifts (sel_shift[2:1]),
//   sel_out and prop_carry act in the second stage and pass through one more
//   register here so each control meets the data it belongs to. sel_shift is
//   reassembled with its low bit combinational and its high bits registered.
//   sel_acc is not decoded here: it is a runtime input the top level pipelines.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module ctrl #(
    localparam int NUM_PAIR   = 8,
    localparam int NUM_DP8    = 16,
    localparam int SEL_WIDTH  = 2,
    localparam int OP_WIDTH   = 2,
    localparam int NUM_SHIFT  = 3,
    localparam int NUM_LEVEL  = 3,
    localparam int SHIFT_HI   = 2,
    localparam int MODE_WIDTH = 4,
    localparam int NUM_ENTRY  = 16
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic [MODE_WIDTH-1:0] mode_i,
    output logic [ SEL_WIDTH-1:0] sel_a_o       [0:NUM_PAIR-1],
    output logic [ SEL_WIDTH-1:0] sel_b_o       [0:NUM_PAIR-1],
    output logic [  OP_WIDTH-1:0] ctr_l_o       [0:NUM_PAIR-1],
    output logic [  OP_WIDTH-1:0] ctr_h_o       [0:NUM_PAIR-1],
    output logic                  is_signed_a_o [ 0:NUM_DP8-1],
    output logic                  is_signed_b_o [ 0:NUM_DP8-1],
    output logic [ NUM_SHIFT-1:0] sel_shift_o,
    output logic [ SEL_WIDTH-1:0] sel_out_o,
    output logic [ NUM_LEVEL-1:0] en_level_o,
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

    localparam logic [OP_WIDTH-1:0] CTR_L_LUT [0:NUM_ENTRY-1][0:NUM_PAIR-1] = '{
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd1, 2'd1, 2'd1, 2'd1, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd2, 2'd0, 2'd0},
        '{2'd0, 2'd2, 2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0}
    };

    localparam logic [OP_WIDTH-1:0] CTR_H_LUT [0:NUM_ENTRY-1][0:NUM_PAIR-1] = '{
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd0, 2'd3, 2'd0, 2'd0, 2'd0, 2'd3, 2'd0, 2'd0},
        '{2'd0, 2'd3, 2'd0, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0}
    };

    localparam logic IS_SIGNED_A_LUT [0:NUM_ENTRY-1][0:NUM_DP8-1] = '{
        '{default: 1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0},
        '{default: 1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0},
        '{1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0},
        '{1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0}
    };

    localparam logic IS_SIGNED_B_LUT [0:NUM_ENTRY-1][0:NUM_DP8-1] = '{
        '{default: 1'b0},
        '{default: 1'b1},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{default: 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0},
        '{1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0}
    };

    localparam logic [NUM_SHIFT-1:0] SEL_SHIFT_LUT [0:NUM_ENTRY-1] = '{
        3'b000, 3'b000, 3'b010, 3'b011, 3'b000, 3'b000, 3'b010, 3'b011,
        3'b111, 3'b111, 3'b010, 3'b010, 3'b111, 3'b000, 3'b000, 3'b000
    };

    localparam logic [SEL_WIDTH-1:0] SEL_OUT_LUT [0:NUM_ENTRY-1] = '{
        2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd2, 2'd3, 2'd2,
        2'd3, 2'd2, 2'd1, 2'd2, 2'd2, 2'd0, 2'd0, 2'd0
    };

    logic [MODE_WIDTH-1:0] mode_d  [0:0];
    logic [MODE_WIDTH-1:0] mode_q1 [0:0];

    assign mode_d[0] = mode_i;

    reg_n #(.WIDTH(MODE_WIDTH), .SIZE(1)) reg_mode_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(mode_d), .q_o(mode_q1)
    );

    logic [NUM_SHIFT-1:0] sel_shift_c;
    logic [SEL_WIDTH-1:0] sel_out_c;
    logic                 prop_carry_c;

    genvar p, i;
    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_disp
            assign sel_a_o[p] = SEL_A_LUT[mode_q1[0]][p];
            assign sel_b_o[p] = SEL_B_LUT[mode_q1[0]][p];
            assign ctr_l_o[p] = CTR_L_LUT[mode_q1[0]][p];
            assign ctr_h_o[p] = CTR_H_LUT[mode_q1[0]][p];
        end
        for (i = 0; i < NUM_DP8; i++) begin : gen_pe
            assign is_signed_a_o[i] = IS_SIGNED_A_LUT[mode_q1[0]][i];
            assign is_signed_b_o[i] = IS_SIGNED_B_LUT[mode_q1[0]][i];
        end
    endgenerate

    assign sel_shift_c  = SEL_SHIFT_LUT[mode_q1[0]];
    assign sel_out_c    = SEL_OUT_LUT[mode_q1[0]];
    assign prop_carry_c = (SEL_OUT_LUT[mode_q1[0]] != '0);

    logic [ SHIFT_HI-1:0] shifthi_d [0:0];
    logic [ SHIFT_HI-1:0] shifthi_q [0:0];
    logic [SEL_WIDTH-1:0] selout_d  [0:0];
    logic [SEL_WIDTH-1:0] selout_q  [0:0];
    logic                 propc_d   [0:0];
    logic                 propc_q   [0:0];

    assign shifthi_d[0] = sel_shift_c[NUM_SHIFT-1:1];
    assign selout_d[0]  = sel_out_c;
    assign propc_d[0]   = prop_carry_c;

    reg_n #(.WIDTH(SHIFT_HI), .SIZE(1)) reg_shifthi_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(shifthi_d), .q_o(shifthi_q)
    );
    reg_n #(.WIDTH(SEL_WIDTH), .SIZE(1)) reg_selout_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(selout_d), .q_o(selout_q)
    );
    reg_n #(.WIDTH(1), .SIZE(1)) reg_propc_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(propc_d), .q_o(propc_q)
    );

    assign sel_shift_o  = {shifthi_q[0], sel_shift_c[0]};
    assign sel_out_o    = selout_q[0];
    assign en_level_o   = {&selout_q[0], selout_q[0][1], |selout_q[0]};
    assign prop_carry_o = propc_q[0];

endmodule
