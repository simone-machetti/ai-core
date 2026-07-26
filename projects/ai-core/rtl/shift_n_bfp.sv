// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized fill-windowed variable right shifter. Operates on SIZE input
//   words, each WIDTH bits wide: every word is right-shifted by the shared
//   amount amt_i inside the 2*WIDTH window {fill_i, in_i}, and the low WIDTH
//   bits of the shifted window are returned:
//       out_o = ({fill_i, in_i} >> amt_i)[WIDTH-1:0]
//   fill_i supplies the bits that stream in from above: replicate the word's
//   sign for a plain arithmetic shift, or pass the upper neighbour's word to
//   form a distributed double-width shifter (lane fusion). Amounts at or
//   beyond 2*WIDTH resolve to the extension of fill_i. The window is
//   sign-extended above fill_i when IS_SIGNED (arithmetic shift), zero-
//   extended otherwise (logical shift).
//
// Parameters:
//   WIDTH     - word width
//   SIZE      - number of words (all share the amount)
//   AMT_WIDTH - shift-amount width
//   IS_SIGNED - 1: arithmetic (sign-extend the window), 0: logical
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module shift_n_bfp #(
    parameter int WIDTH     = 8,
    parameter int SIZE      = 4,
    parameter int AMT_WIDTH = $clog2(2 * WIDTH + 1),
    parameter bit IS_SIGNED = 1'b1
)(
    input  logic [    WIDTH-1:0] in_i   [0:SIZE-1],
    input  logic [    WIDTH-1:0] fill_i [0:SIZE-1],
    input  logic [AMT_WIDTH-1:0] amt_i,
    output logic [    WIDTH-1:0] out_o  [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_shift
            assign out_o[i] = IS_SIGNED
                ? WIDTH'($signed({fill_i[i], in_i[i]}) >>> amt_i)
                : WIDTH'({fill_i[i], in_i[i]} >> amt_i);
        end
    endgenerate

endmodule
