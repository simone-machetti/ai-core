// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   B-operand centering gate for the square datapath. For each of SIZE int4
//   words it produces the centered signed nibble the square PE expects, or a
//   real zero when the DP8 is idle.
//
//   Centering flips the nibble MSB (bit WIDTH-1) iff the nibble is UNSIGNED
//   (~is_signed_i), mapping it to a signed value in [-8,7]. zero_i forces the
//   word to 0 (idle DP8), applied after centering so the square lane becomes a
//   genuine hardware zero. This replaces gate_b_n's pass/zero/negate: the
//   complex-mode B-negate has moved into pe_array_sqr, so there is no negate
//   and no carry chain here.
//
// Parameters:
//   WIDTH - bit width of each word (int4 = 4)
//   SIZE  - number of words (all share is_signed_i / zero_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module gate_b_n_sqr #(
    parameter int WIDTH = 4,
    parameter int SIZE  = 8
)(
    input  logic [WIDTH-1:0] in_i        [0:SIZE-1],
    input  logic             is_signed_i,
    input  logic             zero_i,
    output logic [WIDTH-1:0] out_o       [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_lane
            assign out_o[i] = zero_i ? '0 :
                {in_i[i][WIDTH-1] ^ ~is_signed_i, in_i[i][WIDTH-2:0]};
        end
    endgenerate

endmodule
