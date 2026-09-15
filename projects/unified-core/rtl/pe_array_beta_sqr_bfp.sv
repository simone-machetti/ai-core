// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Beta generator for the square-BFP PE - the per-column B-only correction,
//   made tree-less. It is pe_array_beta_sqr stripped of the 4-level crossed
//   tree, the L0 register, the operand isolation, and the complex-mode block
//   negate: just the 16 dp_8_beta_sqr leaves, whose per-DP8 square-sums BETA_DP8
//   are one's-complemented at the output so the module emits the 16 per-DP8
//   -beta carry-save pairs (each pair resolves to -BETA_DP8 - 2; the deferred
//   +2 per DP8 is folded into const_sqr_bfp).
//
//   These pairs feed pe_array_sqr_bfp's L0 combine directly (no reduction here).
//   The generator is NEG-AGNOSTIC: it always emits -beta; the block negate for
//   modes 10/11 is done in pe_array_sqr_bfp. zero_i is kept (unlike alpha): the
//   beta low block's fixed -8 would inject (-8)^2 = 64 per lane on a
//   dispatcher-zeroed idle DP8, so dp_8_beta_sqr forces that block to a real
//   zero on zero_i.
//
//   Combinational (dp_8_beta_sqr is combinational; the pipeline register lives
//   in pe_array_sqr_bfp's L0). Fanned into every PE of the column. 18-bit outputs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_array_beta_sqr_bfp #(
    localparam int NUM_DP8     = 16,
    localparam int B_DP8_WIDTH = 32,
    localparam int LANES       = 8,
    localparam int IN_WIDTH_B  = 4,
    localparam int DP8_WIDTH   = 18
)(
    input  logic [B_DP8_WIDTH-1:0] b_dp8_i       [0:NUM_DP8-1],
    input  logic                   is_signed_a_i [0:NUM_DP8-1],
    input  logic                   zero_i        [0:NUM_DP8-1],
    output logic [  DP8_WIDTH-1:0] beta_sum_o    [0:NUM_DP8-1],
    output logic [  DP8_WIDTH-1:0] beta_carry_o  [0:NUM_DP8-1]
);

    logic [DP8_WIDTH-1:0] dp8_sum   [0:NUM_DP8-1];
    logic [DP8_WIDTH-1:0] dp8_carry [0:NUM_DP8-1];

    genvar i, ln;

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
            logic [IN_WIDTH_B-1:0] b_lane [0:LANES-1];
            for (ln = 0; ln < LANES; ln++) begin : gen_lane
                assign b_lane[ln] = b_dp8_i[i][ln*IN_WIDTH_B +: IN_WIDTH_B];
            end

            dp_8_beta_sqr dp_8_beta_sqr_i (
                .b_i          (b_lane),
                .is_signed_a_i(is_signed_a_i[i]),
                .zero_i       (zero_i[i]),
                .sum_o        (dp8_sum[i]),
                .carry_o      (dp8_carry[i])
            );

            assign beta_sum_o[i]   = ~dp8_sum[i];
            assign beta_carry_o[i] = ~dp8_carry[i];
        end
    endgenerate

endmodule
