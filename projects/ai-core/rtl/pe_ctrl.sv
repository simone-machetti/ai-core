// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Combinational mode decoder for the PE. Maps the 4-bit mode_i to every
//   internal control the datapath needs:
//     - disp_array : block selects sel_a/sel_b and B-gate controls ctr_l/ctr_h
//     - pe_array   : per-DP8 signedness is_signed_a/is_signed_b and the tree
//                    shift enables sel_shift
//     - acc_array  : tap-level select sel_out and lane-fusion carry enable
//                    prop_carry (asserted whenever the result spans a lane pair,
//                    i.e. the tap level is above L0)
//   Built as a lookup table indexed by the mode bits: each control is a constant
//   array with one row per mode. Rows are populated for the 11 valid modes
//   (1-3, 5-12); the unused indices 0, 4, 13-15 default to zero.
//
//   Purely combinational - it holds no state. All pipeline alignment (delaying
//   each control to meet its data) lives in the enclosing top level. sel_acc is
//   not decoded here: it is a runtime input the top level pipelines alongside
//   mode.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_ctrl #(
    localparam int NUM_PAIR   = 8,
    localparam int NUM_DP8    = 16,
    localparam int SEL_WIDTH  = 2,
    localparam int OP_WIDTH   = 2,
    localparam int NUM_SHIFT  = 3,
    localparam int MODE_WIDTH = 4,
    localparam int NUM_ENTRY  = 16
)(
    input  logic [MODE_WIDTH-1:0] mode_i,
    output logic [ SEL_WIDTH-1:0] sel_a_o       [0:NUM_PAIR-1],
    output logic [ SEL_WIDTH-1:0] sel_b_o       [0:NUM_PAIR-1],
    output logic [  OP_WIDTH-1:0] ctr_l_o       [0:NUM_PAIR-1],
    output logic [  OP_WIDTH-1:0] ctr_h_o       [0:NUM_PAIR-1],
    output logic                  is_signed_a_o [0:NUM_DP8-1],
    output logic                  is_signed_b_o [0:NUM_DP8-1],
    output logic [ NUM_SHIFT-1:0] sel_shift_o,
    output logic [ SEL_WIDTH-1:0] sel_out_o,
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

    genvar p, i;

    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_disp
            assign sel_a_o[p] = SEL_A_LUT[mode_i][p];
            assign sel_b_o[p] = SEL_B_LUT[mode_i][p];
            assign ctr_l_o[p] = CTR_L_LUT[mode_i][p];
            assign ctr_h_o[p] = CTR_H_LUT[mode_i][p];
        end
        for (i = 0; i < NUM_DP8; i++) begin : gen_pe
            assign is_signed_a_o[i] = IS_SIGNED_A_LUT[mode_i][i];
            assign is_signed_b_o[i] = IS_SIGNED_B_LUT[mode_i][i];
        end
    endgenerate

    assign sel_shift_o  = SEL_SHIFT_LUT[mode_i];
    assign sel_out_o    = SEL_OUT_LUT[mode_i];
    assign prop_carry_o = (SEL_OUT_LUT[mode_i] != '0);

endmodule
