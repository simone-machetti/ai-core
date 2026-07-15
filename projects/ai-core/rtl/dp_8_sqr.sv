// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   DP8 (8x4) square-sum core - the add-then-square replacement for dp_8 in the
//   square datapath. Takes eight int8 x int4 lanes as *pre-centered* signed
//   nibbles (the dispatcher has already biased every originally-unsigned nibble
//   by -8, so every nibble is signed [-8,7]) and returns the raw square-sum
//   S_DP8 in carry-save form (sum_o, carry_o). Fixed size - 8 lanes.
//
//   Each int8 a splits into two signed nibbles {AH, AL} = a_i[7:4], a_i[3:0];
//   b_i is the single signed nibble b. Per lane the 8x4 multiply becomes two 4x4
//   add-then-squares: (AH+b) and (AL+b), each a 5-bit signed value in [-16,14]
//   fed to s_5_bit_sqr (9-bit unsigned square). The eight AH squares and the
//   eight AL squares are each reduced by an unsigned CPR 8:2; the AH block is
//   weighted 2^4 (<< 4) and the two blocks combined by an unsigned CPR 4:2:
//       S_DP8 = 2^4 * sum_k (AH_k+b_k)^2  +  sum_k (AL_k+b_k)^2
//   No alpha/beta/C/half here - this core is purely the square-sum; the
//   compensation is applied downstream (acc_array_sqr).
//
//   Unlike dp_8, S_DP8 is a sum of squares and therefore *non-negative*: the
//   carry-save output is unsigned and carries no sign-consistency contract (the
//   hardest property of dp_8 simply vanishes). All three compressors run
//   IS_SIGNED = 0.
//
//   Widths, minimum for this size (parallels dp_8):
//     stage                    width   note
//     -----------------------  -----   -----------------------------------------
//     centered nibble add        5     signed (AH/AL + b) in [-16,14]
//     s_5_bit_sqr output         9     unsigned square in [0,256]
//     per-block CPR 8:2 (x2)    12     9 + clog2(8), unsigned sum-of-8 <= 2048
//     weight-2^4 align (<< 4)   16     12b block row shifted << 4
//     final CPR 4:2 (EXT = 2)   18     four unsigned rows -> two rows
//     output                    18     16b value (S_DP8 <= 34816) + 2 guard bits
//   Combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module dp_8_sqr #(
    localparam int LANES      = 8,
    localparam int IN_WIDTH_A = 8,
    localparam int IN_WIDTH_B = 4,
    localparam int NIB_WIDTH  = 4,
    localparam int SUM_WIDTH  = 5,
    localparam int SQ_WIDTH   = 9,
    localparam int CPR8_WIDTH = SQ_WIDTH + $clog2(LANES),
    localparam int NUM_BLK    = 2,
    localparam int SHIFT_AH   = 4,
    localparam int FINAL_IN   = CPR8_WIDTH + SHIFT_AH,
    localparam int FINAL_EXT  = 2,
    localparam int OUT_WIDTH  = FINAL_IN + FINAL_EXT
)(
    input  logic [IN_WIDTH_A-1:0] a_i [0:LANES-1],
    input  logic [IN_WIDTH_B-1:0] b_i [0:LANES-1],
    output logic [ OUT_WIDTH-1:0] sum_o,
    output logic [ OUT_WIDTH-1:0] carry_o
);

    logic [SQ_WIDTH-1:0] sq_ah [0:LANES-1];
    logic [SQ_WIDTH-1:0] sq_al [0:LANES-1];

    genvar k;
    generate
        for (k = 0; k < LANES; k++) begin : gen_lane
            logic signed [NIB_WIDTH-1:0] ah;
            logic signed [NIB_WIDTH-1:0] al;
            logic signed [NIB_WIDTH-1:0] b;
            logic signed [SUM_WIDTH-1:0] add_ah;
            logic signed [SUM_WIDTH-1:0] add_al;

            assign ah = a_i[k][NIB_WIDTH +: NIB_WIDTH];
            assign al = a_i[k][0         +: NIB_WIDTH];
            assign b  = b_i[k];

            assign add_ah = ah + b;
            assign add_al = al + b;

            s_5_bit_sqr sqr_ah_i (.in_i(add_ah), .out_o(sq_ah[k]));
            s_5_bit_sqr sqr_al_i (.in_i(add_al), .out_o(sq_al[k]));
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
