// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Beta DP8 (8x4) square-sum core - the B-only generator DP8 for the square
//   datapath. Same structure and widths as dp_8_sqr, but with the A operand
//   removed. The single pre-centered b nibble feeds two blocks, each squared:
//       BETA_DP8 = 2^4 * sum_k (B_k - 8*au)^2  +  sum_k (B_k - 8)^2
//   The high (<< 4) block subtracts the removed A-high's -8 (gate_n_sqr, driven
//   by is_signed_a: au = ~is_signed_a); the low block subtracts a *fixed* -8
//   (gate_n_beta_sqr) because the removed A-low nibble is structurally unsigned,
//   or forces a real zero on idle. 16 s_5_bit_sqr, two unsigned CPR 8:2, high
//   block << 4, one unsigned CPR 4:2 -> 18-bit unsigned carry-save square-sum
//   (no alpha/beta/C/half - applied downstream by acc_array_sqr).
//
//   Unlike alpha, the low block's -8 is fixed and would inject (-8)^2 = 64 per
//   lane on a dispatcher-zeroed idle DP8, so zero_i forces that block to a real
//   zero (the high block self-cleans via is_signed_a = 1). All three
//   compressors run IS_SIGNED = 0. Widths identical to dp_8_sqr (18-bit out).
//   Combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module dp_8_beta_sqr #(
    localparam int LANES      = 8,
    localparam int IN_WIDTH_B = 4,
    localparam int SUM_WIDTH  = 5,
    localparam int SQ_WIDTH   = 9,
    localparam int CPR8_WIDTH = SQ_WIDTH + $clog2(LANES),
    localparam int NUM_BLK    = 2,
    localparam int SHIFT_AH   = 4,
    localparam int FINAL_IN   = CPR8_WIDTH + SHIFT_AH,
    localparam int FINAL_EXT  = 2,
    localparam int OUT_WIDTH  = FINAL_IN + FINAL_EXT
)(
    input  logic [IN_WIDTH_B-1:0] b_i           [0:LANES-1],
    input  logic                  is_signed_a_i,
    input  logic                  zero_i,
    output logic [ OUT_WIDTH-1:0] sum_o,
    output logic [ OUT_WIDTH-1:0] carry_o
);

    logic [SUM_WIDTH-1:0] arg_ah [0:LANES-1];
    logic [SUM_WIDTH-1:0] arg_al [0:LANES-1];
    logic [ SQ_WIDTH-1:0] sq_ah  [0:LANES-1];
    logic [ SQ_WIDTH-1:0] sq_al  [0:LANES-1];

    gate_n_sqr #(.WIDTH(IN_WIDTH_B), .SIZE(LANES)) gate_n_sqr_ah_i (
        .in_i(b_i), .is_signed_i(is_signed_a_i), .out_o(arg_ah)
    );

    gate_n_beta_sqr #(.WIDTH(IN_WIDTH_B), .SIZE(LANES)) gate_n_beta_sqr_al_i (
        .in_i(b_i), .zero_i(zero_i), .out_o(arg_al)
    );

    genvar k;
    generate
        for (k = 0; k < LANES; k++) begin : gen_sqr
            s_5_bit_sqr sqr_ah_i (.in_i(arg_ah[k]), .out_o(sq_ah[k]));
            s_5_bit_sqr sqr_al_i (.in_i(arg_al[k]), .out_o(sq_al[k]));
        end
    endgenerate

    logic [CPR8_WIDTH-1:0] ah_sum;
    logic [CPR8_WIDTH-1:0] ah_carry;
    logic [CPR8_WIDTH-1:0] al_sum;
    logic [CPR8_WIDTH-1:0] al_carry;

    cpr_w_n #(
        .IN_WIDTH (SQ_WIDTH),
        .IN_SIZE  (LANES),
        .EXT      ($clog2(LANES)),
        .IS_SIGNED(1'b0)
    ) cpr_w_n_ah_i (
        .in_i   (sq_ah),
        .sum_o  (ah_sum),
        .carry_o(ah_carry)
    );

    cpr_w_n #(
        .IN_WIDTH (SQ_WIDTH),
        .IN_SIZE  (LANES),
        .EXT      ($clog2(LANES)),
        .IS_SIGNED(1'b0)
    ) cpr_w_n_al_i (
        .in_i   (sq_al),
        .sum_o  (al_sum),
        .carry_o(al_carry)
    );

    logic [FINAL_IN-1:0] final_in [0:NUM_BLK*2-1];

    assign final_in[0] = FINAL_IN'(ah_sum)   << SHIFT_AH;
    assign final_in[1] = FINAL_IN'(ah_carry) << SHIFT_AH;
    assign final_in[2] = FINAL_IN'(al_sum);
    assign final_in[3] = FINAL_IN'(al_carry);

    cpr_w_n #(
        .IN_WIDTH (FINAL_IN),
        .IN_SIZE  (NUM_BLK*2),
        .EXT      (FINAL_EXT),
        .IS_SIGNED(1'b0)
    ) cpr_w_n_final_i (
        .in_i   (final_in),
        .sum_o  (sum_o),
        .carry_o(carry_o)
    );

endmodule
