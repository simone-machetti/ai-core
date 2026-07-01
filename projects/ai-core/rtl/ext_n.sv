// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized extender. Widens each of SIZE input words from WIDTH bits to
//   OUT_WIDTH = WIDTH + EXT bits by prepending EXT bits at the top. The added
//   bits replicate the sign bit when is_signed_i is 1 (sign extension) or are
//   zero otherwise (zero extension). The is_signed_i select is a runtime signal
//   so the extension mode can change with the operating mode. Purely
//   combinational, applied independently to every word.
//
// Parameters:
//   WIDTH - bit width of each input word
//   SIZE  - number of input words
//   EXT   - number of bits added at the top of each word
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module ext_n #(
    parameter int WIDTH = 8,
    parameter int SIZE  = 4,
    parameter int EXT   = 4,

    localparam int OUT_WIDTH = WIDTH + EXT
)(
    input  logic [    WIDTH-1:0] in_i        [0:SIZE-1],
    input  logic                 is_signed_i,
    output logic [OUT_WIDTH-1:0] out_o       [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_ext
            assign out_o[i] = {{EXT{(is_signed_i ? in_i[i][WIDTH-1] : 1'b0)}}, in_i[i]};
        end
    endgenerate

endmodule
