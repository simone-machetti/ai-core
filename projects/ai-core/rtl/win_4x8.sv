// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Winograd partial product generator for a 64-element 4×8 array.
//   Splits the 64 inputs into 8 lanes of 8 pairs each. Within each lane,
//   add_mult_array computes the Winograd product:
//     (a[i+1] + b[i]) * (a[i] + b[i+1])
//   for each adjacent pair, halving the multiplier count vs. baseline.
//   Results are compressed by cpr_n_2 and shift-aligned for cpr_tree.
//
// Parameters:
//   MULT_TYPE - 0 = Radix-4 Booth, 1 = Radix-8 Booth
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module win_4x8 #(
    parameter int MULT_TYPE = 0,

    localparam int IN_SIZE      = 64,
    localparam int IN_WIDTH_A   = 4,
    localparam int IN_WIDTH_B   = 8,
    localparam int NUM_LANES    = 8,
    localparam int PP_PER_MUL   = MULT_TYPE == 0 ? ((IN_WIDTH_B + 2) + 1) / 2 : ((IN_WIDTH_B + 2) + 2) / 3,
    localparam int PP_SIZE      = 2 * PP_PER_MUL * NUM_LANES,
    localparam int CPR_IN_SIZE  = IN_SIZE / NUM_LANES / 2,
    localparam int CPR_IN_WIDTH = MULT_TYPE == 0 ? (IN_WIDTH_B + 2) + 2 : (IN_WIDTH_B + 2) + 3,
    localparam int PP_SHIFT     = MULT_TYPE == 0 ? 2 : 3,
    localparam int PP_WIDTH     = CPR_IN_WIDTH + $clog2(CPR_IN_SIZE) + 1 + ((PP_PER_MUL - 1) * PP_SHIFT)
)(
    input  logic [IN_WIDTH_A-1:0] a_i  [0:IN_SIZE-1],
    input  logic [IN_WIDTH_B-1:0] b_i  [0:IN_SIZE-1],
    output logic [  PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    genvar lane, cpr, i;
    generate

        localparam int MULT_ARRAY_IN_SIZE = IN_SIZE / NUM_LANES;
        localparam int MULT_ARRAY_PP_SIZE = PP_PER_MUL * MULT_ARRAY_IN_SIZE / 2;
        localparam bit IS_SIGNED          = 1;

        for (lane = 0; lane < NUM_LANES; lane++) begin : gen_lane

            localparam int MULT_ARRAY_IN_OFFSET = lane * MULT_ARRAY_IN_SIZE;

            logic [CPR_IN_WIDTH-1:0] pp [0:MULT_ARRAY_PP_SIZE-1];

            add_mult_array #(
                .IN_SIZE   (MULT_ARRAY_IN_SIZE),
                .IN_WIDTH_A(IN_WIDTH_A),
                .IN_WIDTH_B(IN_WIDTH_B),
                .MULT_TYPE (MULT_TYPE),
                .IS_SIGNED (IS_SIGNED)
            ) add_mult_array_i (
                .a_i (a_i[MULT_ARRAY_IN_OFFSET +: MULT_ARRAY_IN_SIZE]),
                .b_i (b_i[MULT_ARRAY_IN_OFFSET +: MULT_ARRAY_IN_SIZE]),
                .pp_o(pp)
            );

            localparam int CPR_N_2_IN_SIZE      = MULT_ARRAY_IN_SIZE / 2;
            localparam int CPR_N_2_MAX_EXT_BITS = -1;
            localparam int CPR_N_2_PP_OUT_WIDTH = CPR_IN_WIDTH + $clog2(CPR_N_2_IN_SIZE) + 1;

            for (cpr = 0; cpr < PP_PER_MUL; cpr++) begin : gen_cpr_n_2

                localparam int CPR_N_2_OUT_OFFSET = (lane * PP_PER_MUL * 2) + (cpr * 2);
                localparam int CPR_N_2_OUT_SHIFT  = cpr * PP_SHIFT;
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

    endgenerate

endmodule
