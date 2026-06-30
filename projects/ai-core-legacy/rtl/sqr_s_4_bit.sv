// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Signed 4-bit squarer. Converts the 2's-complement input to its absolute
//   value using sign-bit XOR on each data bit followed by a ripple half-adder
//   increment chain. The resulting 3-bit magnitude is then squared by
//   sqr_u_3_bit; the final carry of the increment chain becomes bit 6 of the
//   8-bit output (bit 7 is always 0, since |min| = 8 and 8^2 = 64 fits in 7
//   bits).
// -----------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */

`timescale 1 ns/1 ps

module sqr_s_4_bit (
    input  logic [3:0] in_i,
    output logic [7:0] out_o
);

    logic [2:0] xor_gates;
    logic       sign;
    logic [2:0] carry;
    logic [2:0] sum;

    assign sign         = in_i[3];
    assign xor_gates[0] = in_i[0] ^ sign;
    assign xor_gates[1] = in_i[1] ^ sign;
    assign xor_gates[2] = in_i[2] ^ sign;

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

    sqr_u_3_bit sqr_u_3_bit_i (
        .in_i (sum),
        .out_o(out_o[5:0])
    );

    assign out_o[6] = carry[2];
    assign out_o[7] = 1'b0;

endmodule
