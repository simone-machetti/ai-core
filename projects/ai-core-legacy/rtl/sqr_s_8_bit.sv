// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Signed 8-bit squarer. Converts the 2's-complement input to its 7-bit
//   magnitude using sign-bit XOR and a ripple half-adder increment chain, then
//   calls sqr_u_7_bit on sum[6:0]. The increment carry (carry[6]) is only set
//   for x = -128 (|x| = 128 = 2^7), whose square is 2^14; it is wired directly
//   to out_o[14], which sqr_u_7_bit can never assert (max output 127^2 < 2^14).
//   Output is 16 bits wide; out_o[15] is always 0 (128^2 = 16384 fits in 15 b).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module sqr_s_8_bit (
    input  logic [7:0]  in_i,
    output logic [15:0] out_o
);

    logic [6:0] xor_gates;
    logic       sign;
    logic [6:0] carry;
    logic [6:0] sum;

    assign sign         = in_i[7];
    assign xor_gates[0] = in_i[0] ^ sign;
    assign xor_gates[1] = in_i[1] ^ sign;
    assign xor_gates[2] = in_i[2] ^ sign;
    assign xor_gates[3] = in_i[3] ^ sign;
    assign xor_gates[4] = in_i[4] ^ sign;
    assign xor_gates[5] = in_i[5] ^ sign;
    assign xor_gates[6] = in_i[6] ^ sign;

    ha ha_0_i (
        .in_i  (xor_gates[0]),
        .cin_i (sign),
        .sum_o (sum[0]),
        .cout_o(carry[0])
    );

    ha ha_1_i (
        .in_i  (xor_gates[1]),
        .cin_i (carry[0]),
        .sum_o (sum[1]),
        .cout_o(carry[1])
    );

    ha ha_2_i (
        .in_i  (xor_gates[2]),
        .cin_i (carry[1]),
        .sum_o (sum[2]),
        .cout_o(carry[2])
    );

    ha ha_3_i (
        .in_i  (xor_gates[3]),
        .cin_i (carry[2]),
        .sum_o (sum[3]),
        .cout_o(carry[3])
    );

    ha ha_4_i (
        .in_i  (xor_gates[4]),
        .cin_i (carry[3]),
        .sum_o (sum[4]),
        .cout_o(carry[4])
    );

    ha ha_5_i (
        .in_i  (xor_gates[5]),
        .cin_i (carry[4]),
        .sum_o (sum[5]),
        .cout_o(carry[5])
    );

    ha ha_6_i (
        .in_i  (xor_gates[6]),
        .cin_i (carry[5]),
        .sum_o (sum[6]),
        .cout_o(carry[6])
    );

    logic [13:0] sqr7_out;

    sqr_u_7_bit sqr_u_7_bit_i (
        .in_i (sum[6:0]),
        .out_o(sqr7_out)
    );

    assign out_o = {1'b0, carry[6], sqr7_out};

endmodule
