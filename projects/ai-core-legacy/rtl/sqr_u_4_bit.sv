// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Unsigned 4-bit squarer. Computes out_o = in_i^2 using a minimal
//   combinational logic expression derived from the 4-bit truth table.
//   Output is 8 bits wide (2 * 4 bits).
// -----------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */

`timescale 1 ns/1 ps

module sqr_u_4_bit (
    input  logic [3:0] in_i,
    output logic [7:0] out_o
);

    logic a0, a1, a2, a3;
    
    assign {a3, a2, a1, a0} = in_i;
    assign out_o[0]         = a0;
    assign out_o[1]         = 1'b0;
    assign out_o[2]         = a1 & ~a0;
    assign out_o[3]         = a0 & (a1 ^ a2);
    assign out_o[4]         = (a0 & (a2 ^ a3)) | (a2 & ~a1 & ~a0);
    assign out_o[5]         = (a1 & (a2 ^ a3)) | (a3 & a2 & a0);
    assign out_o[6]         = a3 & (~a2 | a1);
    assign out_o[7]         = a3 & a2;

endmodule
