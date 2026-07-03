// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized conditioning gate for operand B. For each of SIZE input
//   words, WIDTH bits wide, selects one of four results onto the output: the
//   input unchanged (pass), an all-zero word (zero), the input's
//   two's-complement negation (negate), or a carry-chained negation
//   (negate-carry). The 2-bit select sel_i is shared by all words. B needs
//   pass (most modes), zero (idle DP8s, e.g. mode 6) and negation (imaginary B
//   in the complex modes).
//
//   A single WIDTH-bit negation is exact, but an operand split across several
//   gates (e.g. an int8 B as its high and low int4 nibbles in two different
//   gate instances) cannot be negated per gate independently: the two's-
//   complement +1 is a single carry that must ripple from the least-significant
//   word upward. So negate exposes its carry-out (carry_o) and negate-carry
//   adds the incoming carry (carry_i) in place of a fixed +1. Wiring the low
//   gate's carry_o into the high gate's carry_i (low = GATE_NEG, high =
//   GATE_NEG_CARRY) then yields an exact negation of the whole operand. The
//   negation keeps WIDTH bits, so the most-negative value wraps.
//
// Parameters:
//   WIDTH - bit width of each word
//   SIZE  - number of words (all share the select)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module gate_b_n #(
    parameter int WIDTH = 8,
    parameter int SIZE  = 4
)(
    input  logic [WIDTH-1:0] in_i   [0:SIZE-1],
    input  logic             carry_i[0:SIZE-1],
    input  logic [      1:0] sel_i,
    output logic [WIDTH-1:0] out_o  [0:SIZE-1],
    output logic             carry_o[0:SIZE-1]
);

    localparam logic [1:0] GATE_PASS      = 2'b00;
    localparam logic [1:0] GATE_ZERO      = 2'b01;
    localparam logic [1:0] GATE_NEG       = 2'b10;
    localparam logic [1:0] GATE_NEG_CARRY = 2'b11;

    always_comb begin
        for (int i = 0; i < SIZE; i++) begin
            case (sel_i)
                GATE_PASS:      begin out_o[i] = in_i[i]; carry_o[i] = 1'b0; end
                GATE_ZERO:      begin out_o[i] = '0;      carry_o[i] = 1'b0; end
                GATE_NEG:       {carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + 1'b1;
                GATE_NEG_CARRY: {carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + carry_i[i];
                default:        begin out_o[i] = in_i[i]; carry_o[i] = 1'b0; end
            endcase
        end
    end

endmodule
