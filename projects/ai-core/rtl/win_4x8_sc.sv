// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Winograd split-cell partial product generator. Combines the Winograd
//   pairing of win_4x8 with the sub-lane B decomposition of bas_4x8_sc:
//   8 lanes × 2 sub-lanes. Each sub-lane extracts a 4-bit B half and applies
//   add_mult_array + cpr_n_2; sub-lane 1 outputs are shifted by PP_SUB_SHIFT
//   = 4 bits relative to sub-lane 0 to implement B = B_lo + 16 * B_hi.
//
// Parameters:
//   MULT_TYPE - 0 = Radix-4 Booth, 1 = Radix-8 Booth
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module win_4x8_sc #(
    parameter int MULT_TYPE = 0,

    localparam int IN_SIZE       = 64,
    localparam int IN_WIDTH_A    = 4,
    localparam int IN_WIDTH_B    = 8,
    localparam int NUM_LANES     = 8,
    localparam int NUM_SUB_LANES = 2,
    localparam int PP_PER_MUL    = MULT_TYPE == 0 ? ((IN_WIDTH_A + 2) + 1) / 2 : ((IN_WIDTH_A + 2) + 2) / 3,
    localparam int PP_SIZE       = 2 * PP_PER_MUL * NUM_SUB_LANES * NUM_LANES,
    localparam int CPR_IN_SIZE   = IN_SIZE / NUM_LANES,
    localparam int CPR_IN_WIDTH  = MULT_TYPE == 0 ? (IN_WIDTH_A + 2) + 2 : (IN_WIDTH_A + 2) + 3,
    localparam int PP_SHIFT      = MULT_TYPE == 0 ? 2 : 3,
    localparam int PP_SUB_SHIFT  = 4,
    localparam int PP_WIDTH      = CPR_IN_WIDTH + $clog2(CPR_IN_SIZE) + 1 + ((PP_PER_MUL - 1) * PP_SHIFT) + PP_SUB_SHIFT
)(
    input  logic [IN_WIDTH_A-1:0] a_i  [0:IN_SIZE-1],
    input  logic [IN_WIDTH_B-1:0] b_i  [0:IN_SIZE-1],
    output logic [  PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    genvar lane, sub_lane, cpr, i;
    generate

        localparam int MULT_ARRAY_IN_SIZE    = IN_SIZE / NUM_LANES;
        localparam int MULT_ARRAY_IN_WIDTH_B = IN_WIDTH_B / 2;
        localparam int MULT_ARRAY_PP_SIZE    = PP_PER_MUL * MULT_ARRAY_IN_SIZE / 2;

        for (lane = 0; lane < NUM_LANES; lane++) begin : gen_lane

            localparam int MULT_ARRAY_IN_SIZE_BASE = lane * MULT_ARRAY_IN_SIZE;

            for (sub_lane = 0; sub_lane < NUM_SUB_LANES; sub_lane++) begin : gen_sub_lane

                localparam int MULT_ARRAY_IN_WIDTH_BASE = sub_lane * MULT_ARRAY_IN_WIDTH_B;
                localparam bit IS_SIGNED                = sub_lane == 0 ? 0 : 1;

                logic [           IN_WIDTH_A-1:0] a  [0:MULT_ARRAY_IN_SIZE-1];
                logic [MULT_ARRAY_IN_WIDTH_B-1:0] b  [0:MULT_ARRAY_IN_SIZE-1];
                logic [         CPR_IN_WIDTH-1:0] pp [0:MULT_ARRAY_PP_SIZE-1];

                for (i = 0; i < MULT_ARRAY_IN_SIZE; i++) begin
                    assign a[i] = a_i[MULT_ARRAY_IN_SIZE_BASE+i];
                    assign b[i] = b_i[MULT_ARRAY_IN_SIZE_BASE+i][MULT_ARRAY_IN_WIDTH_BASE+:MULT_ARRAY_IN_WIDTH_B];
                end

                add_mult_array #(
                    .IN_SIZE   (MULT_ARRAY_IN_SIZE),
                    .IN_WIDTH_A(IN_WIDTH_A),
                    .IN_WIDTH_B(MULT_ARRAY_IN_WIDTH_B),
                    .MULT_TYPE (MULT_TYPE),
                    .IS_SIGNED (IS_SIGNED)
                ) add_mult_array_i (
                    .a_i (a),
                    .b_i (b),
                    .pp_o(pp)
                );

                localparam int CPR_N_2_IN_SIZE      = MULT_ARRAY_IN_SIZE / 2;
                localparam int CPR_N_2_MAX_EXT_BITS = -1;
                localparam int CPR_N_2_PP_OUT_WIDTH = CPR_IN_WIDTH + $clog2(CPR_N_2_IN_SIZE) + 1;

                for (cpr = 0; cpr < PP_PER_MUL; cpr++) begin : gen_cpr_n_2

                    localparam int CPR_N_2_OUT_OFFSET = (lane * NUM_SUB_LANES * PP_PER_MUL * 2) + (sub_lane * PP_PER_MUL * 2) + (cpr * 2);
                    localparam int CPR_N_2_OUT_SHIFT  = (cpr * PP_SHIFT) + (sub_lane * PP_SUB_SHIFT);
                    localparam int CPR_N_2_OUT_MARG   = PP_WIDTH - CPR_N_2_PP_OUT_WIDTH - CPR_N_2_OUT_SHIFT;
                    localparam int CPR_N_2_OUT_CUT    = CPR_N_2_OUT_MARG > 0 ? CPR_N_2_PP_OUT_WIDTH : CPR_N_2_PP_OUT_WIDTH + CPR_N_2_OUT_MARG;

                    logic [        CPR_IN_WIDTH-1:0] pp_in  [0:CPR_N_2_IN_SIZE-1];
                    logic [CPR_N_2_PP_OUT_WIDTH-1:0] pp_out [                0:1];

                    for (i = 0; i < CPR_N_2_IN_SIZE; i++)
                        assign pp_in[i] = pp[i*PP_PER_MUL+cpr];

                    cpr_n_2 #(
                        .IN_SIZE     (CPR_N_2_IN_SIZE),
                        .IN_WIDTH    (CPR_IN_WIDTH),
                        .MAX_EXT_BITS(CPR_N_2_MAX_EXT_BITS)
                    ) cpr_n_2_i (
                        .in_i   (pp_in),
                        .sum_o  (pp_out[0]),
                        .carry_o(pp_out[1])
                    );

                    if (CPR_N_2_OUT_MARG > 0) begin

                        assign pp_o[CPR_N_2_OUT_OFFSET+0] = {{CPR_N_2_OUT_MARG{pp_out[0][CPR_N_2_OUT_CUT-1]}}, pp_out[0], {CPR_N_2_OUT_SHIFT{1'b0}}};
                        assign pp_o[CPR_N_2_OUT_OFFSET+1] = {{CPR_N_2_OUT_MARG{pp_out[1][CPR_N_2_OUT_CUT-1]}}, pp_out[1], {CPR_N_2_OUT_SHIFT{1'b0}}};

                    end else begin

                        assign pp_o[CPR_N_2_OUT_OFFSET+0] = {pp_out[0][CPR_N_2_OUT_CUT-1:0], {CPR_N_2_OUT_SHIFT{1'b0}}};
                        assign pp_o[CPR_N_2_OUT_OFFSET+1] = {pp_out[1][CPR_N_2_OUT_CUT-1:0], {CPR_N_2_OUT_SHIFT{1'b0}}};

                    end

                end

            end

        end

    endgenerate

endmodule
