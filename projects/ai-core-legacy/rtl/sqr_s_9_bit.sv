// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Signed 9-bit squarer. Same algorithm as sqr_s_5_bit: converts the
//   2's-complement input to its 8-bit magnitude using sign-bit XOR and a
//   ripple half-adder increment chain, then calls sqr_u_8_bit. The carry
//   from the increment chain becomes bit 16 of the 17-bit output.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module sqr_s_9_bit (
    input  logic [8:0]  in_i,
    output logic [16:0] out_o
);

    logic [7:0] xor_gates;
    logic       sign;
    logic [7:0] carry;
    logic [7:0] sum;

    assign sign         = in_i[8];
    assign xor_gates[0] = in_i[0] ^ sign;
    assign xor_gates[1] = in_i[1] ^ sign;
    assign xor_gates[2] = in_i[2] ^ sign;
    assign xor_gates[3] = in_i[3] ^ sign;
    assign xor_gates[4] = in_i[4] ^ sign;
    assign xor_gates[5] = in_i[5] ^ sign;
    assign xor_gates[6] = in_i[6] ^ sign;
    assign xor_gates[7] = in_i[7] ^ sign;

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

    ha ha_7_i (
        .in_i  (xor_gates[7]),
        .cin_i (carry[6]),
        .sum_o (sum[7]),
        .cout_o(carry[7])
    );

    sqr_u_8_bit sqr_u_8_bit_i (
        .in_i (sum),
        .out_o(out_o[15:0])
    );

    assign out_o[16] = carry[7];

endmodule
