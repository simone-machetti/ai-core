// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized bitwise complementer. For each of SIZE input words, WIDTH bits
//   wide, passes the input through when neg_i is 0 or one's-complements it
//   (~word) when neg_i is 1. The select is shared by all words. The invert
//   sibling of gate_n (which zeros); used in pe_array_sqr to relocate the
//   complex-mode block negate onto a carry-save pair: ~sum and ~carry, with the
//   two's-complement +1 per row deferred to the accumulator's C constant.
//
// Parameters:
//   WIDTH - bit width of each word
//   SIZE  - number of words (all share neg_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module comp_n #(
    parameter int WIDTH = 8,
    parameter int SIZE  = 2
)(
    input  logic [WIDTH-1:0] in_i  [0:SIZE-1],
    input  logic             neg_i,
    output logic [WIDTH-1:0] out_o [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_comp
            assign out_o[i] = neg_i ? ~in_i[i] : in_i[i];
        end
    endgenerate

endmodule
