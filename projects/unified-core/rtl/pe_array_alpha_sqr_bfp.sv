// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Alpha generator for the square-BFP PE - the per-row A-only correction, made
//   tree-less. It is pe_array_alpha_sqr stripped of the 4-level crossed tree,
//   the L0 register, the operand isolation, and - crucially - the complex-mode
//   block negate: it is just the 16 dp_8_alpha_sqr leaves, whose per-DP8
//   square-sums ALPHA_DP8 are one's-complemented at the output so the module
//   emits the 16 per-DP8 -alpha carry-save pairs (each pair resolves to
//   -ALPHA_DP8 - 2; the deferred +2 per DP8 is folded into const_sqr_bfp).
//
//   These pairs feed pe_array_sqr_bfp's L0 combine directly (no reduction here).
//   The generator is NEG-AGNOSTIC: it always emits -alpha; the block negate for
//   modes 10/11 is done in pe_array_sqr_bfp (which one's-complements the whole
//   {PE, -alpha, -beta} lo bundle, flipping -alpha back to +alpha). Idle DP8s
//   need no zero port here (ctrl forces is_signed_b = 1, so a dispatcher-zeroed
//   A sign-extends to a real zero inside dp_8_alpha_sqr).
//
//   Combinational (dp_8_alpha_sqr is combinational; the pipeline register lives
//   in pe_array_sqr_bfp's L0). Fanned into every PE of the row. 18-bit outputs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_array_alpha_sqr_bfp #(
    localparam int NUM_DP8     = 16,
    localparam int A_DP8_WIDTH = 64,
    localparam int LANES       = 8,
    localparam int IN_WIDTH_A  = 8,
    localparam int DP8_WIDTH   = 18
)(
    input  logic [A_DP8_WIDTH-1:0] a_dp8_i       [0:NUM_DP8-1],
    input  logic                   is_signed_b_i [0:NUM_DP8-1],
    output logic [  DP8_WIDTH-1:0] alpha_sum_o   [0:NUM_DP8-1],
    output logic [  DP8_WIDTH-1:0] alpha_carry_o [0:NUM_DP8-1]
);

    logic [DP8_WIDTH-1:0] dp8_sum   [0:NUM_DP8-1];
    logic [DP8_WIDTH-1:0] dp8_carry [0:NUM_DP8-1];

    genvar i, ln;

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
            logic [IN_WIDTH_A-1:0] a_lane [0:LANES-1];
            for (ln = 0; ln < LANES; ln++) begin : gen_lane
                assign a_lane[ln] = a_dp8_i[i][ln*IN_WIDTH_A +: IN_WIDTH_A];
            end

            dp_8_alpha_sqr dp_8_alpha_sqr_i (
                .a_i          (a_lane),
                .is_signed_b_i(is_signed_b_i[i]),
                .sum_o        (dp8_sum[i]),
                .carry_o      (dp8_carry[i])
            );

            assign alpha_sum_o[i]   = ~dp8_sum[i];
            assign alpha_carry_o[i] = ~dp8_carry[i];
        end
    endgenerate

endmodule
