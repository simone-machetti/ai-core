// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   1-bit half adder. Computes sum = a ^ cin and cout = a & cin.
// -----------------------------------------------------------------------------

/* verilator lint_off UNOPTFLAT */

`timescale 1 ns/1 ps

module ha (
    input  logic in_i,
    input  logic cin_i,
    output logic sum_o,
    output logic cout_o
);

    assign sum_o  = in_i ^ cin_i;
    assign cout_o = in_i & cin_i;

endmodule
