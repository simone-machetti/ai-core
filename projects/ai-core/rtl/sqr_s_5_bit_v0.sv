// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Signed 5-bit squarer. Same algorithm as sqr_s_4_bit: converts the
//   2's-complement input to its 4-bit magnitude using sign-bit XOR and a
//   ripple half-adder increment chain, then calls sqr_u_4_bit. The carry
//   from the increment chain becomes bit 8 of the 9-bit output.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module sqr_s_5_bit_v0 (
    input  logic [4:0] in_i,
    output logic [8:0] out_o
);

    logic [3:0] xor_gates;
    logic       sign;
    logic [3:0] carry;
    logic [3:0] sum;

    assign sign         = in_i[4];
    assign xor_gates[0] = in_i[0] ^ sign;
    assign xor_gates[1] = in_i[1] ^ sign;
    assign xor_gates[2] = in_i[2] ^ sign;
    assign xor_gates[3] = in_i[3] ^ sign;

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

    sqr_u_4_bit sqr_u_4_bit_i (
        .in_i (sum),
        .out_o(out_o[7:0])
    );

    assign out_o[8] = carry[3];

endmodule
