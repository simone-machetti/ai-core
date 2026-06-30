// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Unsigned 3-bit squarer. Computes out_o = in_i^2 using a minimal
//   combinational logic expression derived from the 3-bit truth table.
//   Output is 6 bits wide (2 * 3 bits).
// -----------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */

`timescale 1 ns/1 ps

module sqr_u_3_bit (
    input  logic [2:0] in_i,
    output logic [5:0] out_o
);

    assign out_o[0] = in_i[0];
    assign out_o[1] = 1'b0;
    assign out_o[2] = in_i[1] & (~in_i[0]);
    assign out_o[3] = in_i[0] & (in_i[2] ^ in_i[1]);
    assign out_o[4] = (in_i[2] & (~in_i[1])) | (in_i[2] & in_i[0]);
    assign out_o[5] = in_i[2] & in_i[1];

endmodule
