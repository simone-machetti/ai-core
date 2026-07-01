// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized two-input adder. Adds in_0_i and in_1_i, each WIDTH bits
//   wide, and produces a (WIDTH + 1)-bit result so the sum never overflows.
//   The is_signed_i select chooses how the operands are extended into the
//   extra bit: signed (sign-extended, two's-complement sum) or unsigned
//   (zero-extended). The low WIDTH bits are identical either way; only the
//   most-significant (overflow) bit differs. is_signed_i is a runtime signal
//   so the mode can switch it - e.g. the low word of a fused accumulator
//   resolves unsigned while the high or standalone word resolves signed.
//
// Parameters:
//   WIDTH - bit width of each operand
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module add_n #(
    parameter int WIDTH = 8,

    localparam int OUT_WIDTH = WIDTH + 1
)(
    input  logic [    WIDTH-1:0] in_0_i,
    input  logic [    WIDTH-1:0] in_1_i,
    input  logic                 is_signed_i,
    output logic [OUT_WIDTH-1:0] out_o
);

    logic [OUT_WIDTH-1:0] ext_0;
    logic [OUT_WIDTH-1:0] ext_1;

    assign ext_0 = {(is_signed_i ? in_0_i[WIDTH-1] : 1'b0), in_0_i};
    assign ext_1 = {(is_signed_i ? in_1_i[WIDTH-1] : 1'b0), in_1_i};
    assign out_o = ext_0 + ext_1;

endmodule
