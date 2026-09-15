// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized conditional left shifter. Operates on SIZE input words, each
//   WIDTH bits wide, and either shifts every word left by SHIFT positions or
//   passes it through unchanged, according to a single select sel_i shared by
//   all words. The output is widened to OUT_WIDTH = WIDTH + SHIFT so the full
//   shifted value is preserved with no truncation. When shifting, the SHIFT
//   low bits are zero-filled; when passing through, the value is extended to
//   OUT_WIDTH (sign-extended when IS_SIGNED, otherwise zero-extended).
//
// Parameters:
//   WIDTH     - bit width of each input word
//   SIZE      - number of input words (all share the selects)
//   SHIFT     - left-shift amount applied when selected
//   IS_SIGNED - pass-through extension: 1 = sign-extend, 0 = zero-extend
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module shift_n #(
    parameter int WIDTH     = 8,
    parameter int SIZE      = 4,
    parameter int SHIFT     = 4,
    parameter bit IS_SIGNED = 1'b1,

    localparam int OUT_WIDTH = WIDTH + SHIFT
)(
    input  logic [    WIDTH-1:0] in_i  [0:SIZE-1],
    input  logic                 sel_i,
    output logic [OUT_WIDTH-1:0] out_o [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_shift
            assign out_o[i] = sel_i
                ? {in_i[i], {SHIFT{1'b0}}}
                : {{SHIFT{(IS_SIGNED ? in_i[i][WIDTH-1] : 1'b0)}}, in_i[i]};
        end
    endgenerate

endmodule
