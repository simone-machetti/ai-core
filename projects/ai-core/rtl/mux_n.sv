// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized N-to-1 multiplexer. Selects one of SIZE input words, each
//   WIDTH bits wide, onto the output according to sel_i. Inputs that must be
//   chosen together (e.g. the high and low halves of a single wider value)
//   are merged into one WIDTH-bit word and presented as a single input, so a
//   plain N-to-1 select covers the paired case without dedicated logic.
//
// Parameters:
//   WIDTH - bit width of each input/output word
//   SIZE  - number of input words to select among
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module mux_n #(
    parameter int WIDTH = 8,
    parameter int SIZE  = 4,

    localparam int SEL_W = (SIZE > 1) ? $clog2(SIZE) : 1
)(
    input  logic [WIDTH-1:0] in_i [0:SIZE-1],
    input  logic [SEL_W-1:0] sel_i,
    output logic [WIDTH-1:0] out_o
);

    assign out_o = in_i[sel_i];

endmodule
