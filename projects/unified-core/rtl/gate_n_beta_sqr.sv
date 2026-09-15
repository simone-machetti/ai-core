// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Fixed-bias / idle-zero variant of gate_n_sqr for the beta generator's low
//   (x1) block. For each of SIZE signed nibbles it *always* subtracts
//   2^(WIDTH-1) when active - the removed A-low nibble is structurally unsigned,
//   so this block is biased unconditionally - unless zero_i forces a real zero
//   (idle DP8). Widens WIDTH -> WIDTH+1.
//
//   Unlike gate_n_sqr there is no sign-extend / pass branch: the low block is
//   never unbiased, so it needs its own zero_i (the fixed -8 does not vanish on
//   a dispatcher-zeroed input the way the flag-driven -8 does - it would inject
//   (-8)^2 = 64 per lane on an idle DP8). Subtract is the same top-bit remap
//   {1, ~in[MSB], in[MSB-1:0]} = in - 2^(WIDTH-1). Combinational.
//
// Parameters:
//   WIDTH - input nibble width (int4 = 4); output is WIDTH+1
//   SIZE  - number of words (all share zero_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module gate_n_beta_sqr #(
    parameter int WIDTH = 4,
    parameter int SIZE  = 8
)(
    input  logic [WIDTH-1:0] in_i   [0:SIZE-1],
    input  logic             zero_i,
    output logic [  WIDTH:0] out_o  [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_lane
            assign out_o[i] = zero_i ? '0 :
                {1'b1, ~in_i[i][WIDTH-1], in_i[i][WIDTH-2:0]};
        end
    endgenerate

endmodule
