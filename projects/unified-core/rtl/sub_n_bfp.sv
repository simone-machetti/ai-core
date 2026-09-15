// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized unsigned difference unit for BFP alignment. Compares two
//   unsigned WIDTH-bit operands and returns the sign and the magnitude of
//   their difference:
//       sign_o = (in_1_i > in_0_i)
//       abs_o  = |in_0_i - in_1_i|
//   The magnitude of the difference of two WIDTH-bit unsigned values always
//   fits in WIDTH bits, so abs_o is WIDTH wide. Companion of shift_n_bfp in
//   align_cell_bfp: sign_o drives every select (which bundle shifts, which
//   exponent is the max) and abs_o is the shift amount.
//
// Parameters:
//   WIDTH - operand width (unsigned)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module sub_n_bfp #(
    parameter  int WIDTH      = 8,
    localparam int DIFF_WIDTH = WIDTH + 1
)(
    input  logic [WIDTH-1:0] in_0_i,
    input  logic [WIDTH-1:0] in_1_i,
    output logic [WIDTH-1:0] abs_o,
    output logic             sign_o
);

    logic signed [DIFF_WIDTH-1:0] diff;

    assign diff   = signed'({1'b0, in_0_i}) - signed'({1'b0, in_1_i});
    assign sign_o = diff[DIFF_WIDTH-1];
    assign abs_o  = sign_o ? WIDTH'(unsigned'(-diff)) : WIDTH'(unsigned'(diff));

endmodule
