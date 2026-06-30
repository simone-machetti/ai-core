// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Sign-extends an IN_WIDTH-bit value to OUT_WIDTH bits by replicating
//   the sign bit in the upper (OUT_WIDTH - IN_WIDTH) positions.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module sign_ext #(
    parameter int IN_WIDTH  = 8,
    parameter int OUT_WIDTH = 16
)(
    input  logic [ IN_WIDTH-1:0] in_i,
    output logic [OUT_WIDTH-1:0] out_o
);

    assign out_o = {{(OUT_WIDTH-IN_WIDTH){in_i[IN_WIDTH-1]}}, in_i};

endmodule
