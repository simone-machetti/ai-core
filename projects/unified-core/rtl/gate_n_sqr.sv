// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Flag-selected bias gate for the square alpha/beta generators. For each of
//   SIZE signed nibbles it produces the 5-bit squarer argument: sign-extend the
//   input when is_signed_i = 1, or subtract 2^(WIDTH-1) when is_signed_i = 0,
//   widening WIDTH -> WIDTH+1.
//
//   This injects the *removed* operand's centering -8 that the alpha/beta
//   squarer arguments need (the dispatcher already centered the live nibble to
//   [-8,7]; this gate adds at most one more -8, never -16). alpha wires
//   is_signed_i = is_signed_b (both its blocks); beta's high (<< 4) block wires
//   is_signed_i = is_signed_a.
//
//   Subtract is the two-gate top-bit remap {1, ~in[MSB], in[MSB-1:0]} =
//   in - 2^(WIDTH-1) (set bit WIDTH, complement bit WIDTH-1, pass the rest);
//   sign-extend is {in[MSB], in}. On idle, ctrl forces is_signed_i = 1, so a
//   dispatcher-zeroed input sign-extends to a real zero - no zero port needed
//   here (see gate_n_beta_sqr for the block that does need one). Combinational.
//
// Parameters:
//   WIDTH - input nibble width (int4 = 4); output is WIDTH+1
//   SIZE  - number of words (all share is_signed_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module gate_n_sqr #(
    parameter int WIDTH = 4,
    parameter int SIZE  = 8
)(
    input  logic [WIDTH-1:0] in_i        [0:SIZE-1],
    input  logic             is_signed_i,
    output logic [  WIDTH:0] out_o       [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_lane
            assign out_o[i] = is_signed_i ?
                {in_i[i][WIDTH-1], in_i[i]} :
                {1'b1, ~in_i[i][WIDTH-1], in_i[i][WIDTH-2:0]};
        end
    endgenerate

endmodule
