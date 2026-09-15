// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Optimized signed 5-bit squarer. Flat single-module, no submodules and no
//   intermediate logic signals. Each output bit is a minimized Boolean function
//   of the five raw input bits derived by Karnaugh-map minimization over the
//   full 32-entry truth table.
//
//   s = in_i[4] (sign bit), a3..a0 = in_i[3:0].
//   out_o[4:0]: sign-independent; same formulas as sqr_u_4_bit on raw bits.
//   out_o[7:5]: sign-dependent; minimized directly from the 5-variable truth table.
//   out_o[8]:   set only for input -16 (magnitude overflows 4 bits → square 256).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module s_5_bit_sqr (
    input  logic [4:0] in_i,
    output logic [8:0] out_o
);

    logic s, a3, a2, a1, a0;

    assign {s, a3, a2, a1, a0} = in_i;

    assign out_o[0] = a0;
    assign out_o[1] = 1'b0;
    assign out_o[2] = a1 & ~a0;
    assign out_o[3] = a0 & (a1 ^ a2);
    assign out_o[4] = (a0 & (a2 ^ a3)) | (a2 & ~a1 & ~a0);
    assign out_o[5] = (~a0 & a1 & (a3 ^ a2)) |
                      ( a0 & (((a3 & (a2 | a1)) | (a2 & a1)) ^ s));
    assign out_o[6] = (~s & a3 & (~a2 | a1)) |
                      ( s & a3 & ~a2 & ~a1 & ~a0) |
                      ( s & ~a3 & ((a1 ^ a0) | (a2 & a1)));
    assign out_o[7] = (~s & a3 & a2) | (s & ~a3 & (a2 ^ (a0 | a1)));
    assign out_o[8] = s & ~a3 & ~a2 & ~a1 & ~a0;

endmodule
