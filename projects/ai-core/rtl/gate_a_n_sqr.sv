// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   A-operand centering gate for the square datapath. For each of SIZE int8
//   words it produces the two centered signed nibbles the square PE expects,
//   or a real zero when the DP8 is idle.
//
//   Centering maps every 4-bit nibble to a signed value in [-8,7] by flipping
//   its MSB iff the nibble is UNSIGNED. Within an int8 {AH, AL}: the low nibble
//   (AL, MSB = bit NIB-1) is always unsigned -> its MSB is flipped
//   unconditionally; the high nibble (AH, MSB = bit WIDTH-1) is flipped iff
//   ~is_signed_i. zero_i forces the whole word to 0 (idle DP8), applied after
//   centering so the square lane becomes a genuine hardware zero (0+0)^2 = 0.
//
// Parameters:
//   WIDTH - bit width of each word (int8 = 8)
//   SIZE  - number of words (all share is_signed_i / zero_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module gate_a_n_sqr #(
    parameter  int WIDTH = 8,
    parameter  int SIZE  = 8,
    localparam int NIB   = 4
)(
    input  logic [WIDTH-1:0] in_i        [0:SIZE-1],
    input  logic             is_signed_i,
    input  logic             zero_i,
    output logic [WIDTH-1:0] out_o       [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_lane
            assign out_o[i] = zero_i ? '0 : {
                in_i[i][WIDTH-1] ^ ~is_signed_i,
                in_i[i][WIDTH-2:NIB],
                ~in_i[i][NIB-1],
                in_i[i][NIB-2:0]
            };
        end
    endgenerate

endmodule
