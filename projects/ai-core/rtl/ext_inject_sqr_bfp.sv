// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Per-DP8 square reconstruction front-end for pe_array_sqr_bfp. For each of
//   NUM_DP8 blocks it folds the square-sum PE (sum/carry from dp_8_sqr), the
//   per-row -alpha and per-column -beta carry-save pairs, and the per-DP8
//   constant into a single carry-save pair 2*P AT THE BLOCK SCALE - no alignment,
//   since PE / -alpha / -beta / const all share the block's own scale E_j. One
//   instantiation processes all NUM_DP8 blocks.
//
//   Per DP8:
//     - gate_n masks -alpha/-beta/const to zero on idle blocks (zero_i): the
//       one's-complemented -alpha/-beta are ~0 = -1 (not 0) and const is a
//       nonzero LUT value, so they must be gated; PE self-zeroes (0^2 = 0) and
//       is not gated.
//     - comp_n one's-complements the six-row {PE, -alpha, -beta} bundle on the
//       negated blocks (neg_i); const bypasses the negate (it already carries the
//       negated per-DP8 constant, un-negated, exactly as const_sqr_bfp emits).
//     - cpr_w_n 7:2 collapses {PE, -alpha, -beta, const} -> {sum, carry} = 2*P.
//
//   Combinational. neg_i is per-DP8: pe_array_sqr_bfp maps the node-indexed
//   block-negate to the DP8 index before driving this block.
//
// Parameters:
//   NUM_DP8   - number of DP8 blocks processed
//   DP8_WIDTH - per-block carry-save word width (holds 2*P at the block scale)
//
// Local parameters (fixed by the square reconstruction):
//   NUM_MANT - negated rows {PE s/c, -alpha s/c, -beta s/c} (6)
//   NUM_GATE - idle-gated rows {-alpha s/c, -beta s/c, const} (5)
//   NUM_ROW  - 7:2 inputs {NUM_MANT rows, const} (7)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module ext_inject_sqr_bfp #(
    parameter  int NUM_DP8   = 16,
    parameter  int DP8_WIDTH = 18,
    localparam int NUM_MANT  = 6,
    localparam int NUM_GATE  = 5,
    localparam int NUM_ROW   = 7
)(
    input  logic [DP8_WIDTH-1:0] pe_sum_i      [0:NUM_DP8-1],
    input  logic [DP8_WIDTH-1:0] pe_carry_i    [0:NUM_DP8-1],
    input  logic [DP8_WIDTH-1:0] alpha_sum_i   [0:NUM_DP8-1],
    input  logic [DP8_WIDTH-1:0] alpha_carry_i [0:NUM_DP8-1],
    input  logic [DP8_WIDTH-1:0] beta_sum_i    [0:NUM_DP8-1],
    input  logic [DP8_WIDTH-1:0] beta_carry_i  [0:NUM_DP8-1],
    input  logic [DP8_WIDTH-1:0] const_i       [0:NUM_DP8-1],
    input  logic                 zero_i        [0:NUM_DP8-1],
    input  logic [  NUM_DP8-1:0] neg_i,
    output logic [DP8_WIDTH-1:0] sum_o         [0:NUM_DP8-1],
    output logic [DP8_WIDTH-1:0] carry_o       [0:NUM_DP8-1]
);

    genvar i;

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
            logic [DP8_WIDTH-1:0] gate_in  [0:NUM_GATE-1];
            logic [DP8_WIDTH-1:0] gate_out [0:NUM_GATE-1];
            logic [DP8_WIDTH-1:0] mant_raw [0:NUM_MANT-1];
            logic [DP8_WIDTH-1:0] mant     [0:NUM_MANT-1];
            logic [DP8_WIDTH-1:0] row      [ 0:NUM_ROW-1];

            assign gate_in[0] = alpha_sum_i[i];
            assign gate_in[1] = alpha_carry_i[i];
            assign gate_in[2] = beta_sum_i[i];
            assign gate_in[3] = beta_carry_i[i];
            assign gate_in[4] = const_i[i];

            gate_n #(.WIDTH(DP8_WIDTH), .SIZE(NUM_GATE)) gate_n_idle_i (
                .in_i(gate_in), .sel_i(zero_i[i]), .out_o(gate_out)
            );

            assign mant_raw[0] = pe_sum_i[i];
            assign mant_raw[1] = pe_carry_i[i];
            assign mant_raw[2] = gate_out[0];
            assign mant_raw[3] = gate_out[1];
            assign mant_raw[4] = gate_out[2];
            assign mant_raw[5] = gate_out[3];

            comp_n #(.WIDTH(DP8_WIDTH), .SIZE(NUM_MANT)) comp_n_i (
                .in_i(mant_raw), .neg_i(neg_i[i]), .out_o(mant)
            );

            assign row[0] = mant[0];
            assign row[1] = mant[1];
            assign row[2] = mant[2];
            assign row[3] = mant[3];
            assign row[4] = mant[4];
            assign row[5] = mant[5];
            assign row[6] = gate_out[4];

            cpr_w_n #(.IN_WIDTH(DP8_WIDTH), .IN_SIZE(NUM_ROW), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
                .in_i(row), .sum_o(sum_o[i]), .carry_o(carry_o[i])
            );
        end
    endgenerate

endmodule
