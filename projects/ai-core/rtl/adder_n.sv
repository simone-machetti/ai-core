// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Signed N-bit adder. Interprets both inputs as SIZE-bit signed values and
//   produces a (SIZE + 1)-bit result to accommodate carry.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module adder_n #(
    parameter int SIZE = 18
)(
    input  logic [SIZE-1:0] in_0_i,
    input  logic [SIZE-1:0] in_1_i,
    output logic [  SIZE:0] out_o
);

    assign out_o = (SIZE)'($signed(in_0_i)) + (SIZE)'($signed(in_1_i));

endmodule
