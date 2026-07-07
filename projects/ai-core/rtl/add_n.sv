// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized two-input adder that resolves a pair of carry-save rows and
//   presents the result split into a sum word and a carry-out. It adds two
//   (WIDTH + CARRY)-bit operands plus a CARRY-bit carry-in and returns the low
//   WIDTH bits as out_o and the top CARRY bits as cout_o:
//       {cout_o, out_o} = in_0_i + in_1_i + cin_i
//   Keeping out_o at WIDTH means the sum going to a register stays WIDTH bits,
//   while cout_o carries the overflow so adjacent lanes can be chained (low lane
//   -> cout_o -> gate -> cin_i of the high lane) to build a wider result from
//   narrow lanes. CARRY is the carry width: 1 for a plain adder, or wider where a
//   single window folds more than two rows and its overflow needs more than one
//   bit - e.g. acc_array folds three 20-bit rows per window (via a 22-bit CPR),
//   whose carry into the next lane is 2 bits, so it uses WIDTH = 20, CARRY = 2.
//
// Parameters:
//   WIDTH - bit width of the sum output
//   CARRY - bit width of the carry-in/out; the operands are WIDTH + CARRY wide
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module add_n #(
    parameter int WIDTH = 8,
    parameter int CARRY = 1
)(
    input  logic [WIDTH+CARRY-1:0] in_0_i,
    input  logic [WIDTH+CARRY-1:0] in_1_i,
    input  logic [      CARRY-1:0] cin_i,
    output logic [      WIDTH-1:0] out_o,
    output logic [      CARRY-1:0] cout_o
);

    assign {cout_o, out_o} = in_0_i + in_1_i + (WIDTH+CARRY)'(cin_i);

endmodule
