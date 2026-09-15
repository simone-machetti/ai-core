// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized extender. Widens each of SIZE input words from WIDTH bits to
//   OUT_WIDTH = WIDTH + EXT bits by prepending EXT bits at the top. The added
//   bits replicate the sign bit when IS_SIGNED (sign extension) or are zero
//   otherwise (zero extension). Purely combinational, applied independently to
//   every word.
//
// Parameters:
//   WIDTH     - bit width of each input word
//   SIZE      - number of input words
//   EXT       - number of bits added at the top of each word
//   IS_SIGNED - extension: 1 = sign-extend, 0 = zero-extend
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module ext_n #(
    parameter int WIDTH     = 8,
    parameter int SIZE      = 4,
    parameter int EXT       = 4,
    parameter bit IS_SIGNED = 1'b1,

    localparam int OUT_WIDTH = WIDTH + EXT
)(
    input  logic [    WIDTH-1:0] in_i  [0:SIZE-1],
    output logic [OUT_WIDTH-1:0] out_o [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_ext
            assign out_o[i] = {{EXT{(IS_SIGNED ? in_i[i][WIDTH-1] : 1'b0)}}, in_i[i]};
        end
    endgenerate

endmodule
