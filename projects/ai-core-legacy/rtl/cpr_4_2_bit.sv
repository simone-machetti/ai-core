// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   1-bit 4:2 compressor cell built from two cascaded full adders.
//   Reduces four single-bit inputs (in_0..in_3) and a carry-in (cin_i) to
//   a sum bit (sum_o), a carry-out to the next bit position (carry_o), and
//   a cout (cout_o) chained to the cin of the adjacent bit's cell.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module cpr_4_2_bit (
    input  logic in_0_i,
    input  logic in_1_i,
    input  logic in_2_i,
    input  logic in_3_i,
    input  logic cin_i,
    output logic cout_o,
    output logic sum_o,
    output logic carry_o
);
    logic s;

    fa fa_0_i (
        .in_0_i(in_0_i),
        .in_1_i(in_1_i),
        .cin_i (in_2_i),
        .sum_o (s),
        .cout_o(cout_o)
    );

    fa fa_1_i (
        .in_0_i(s),
        .in_1_i(in_3_i),
        .cin_i (cin_i),
        .sum_o (sum_o),
        .cout_o(carry_o)
    );

endmodule
