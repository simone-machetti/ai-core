// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized conditioning gate for operand B. For each of SIZE input
//   words, WIDTH bits wide, selects one of three results onto the output: the
//   input unchanged (pass), an all-zero word (zero), or the input's
//   two's-complement negation (negate). The 2-bit select sel_i is shared by
//   all words. B needs all three across the modes: pass (most modes), zero
//   (idle DP8s, e.g. mode 6) and negate (imaginary B in the complex modes).
//   The negation keeps WIDTH bits, so the most-negative value wraps.
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
    input  logic [WIDTH-1:0] in_i  [0:SIZE-1],
    input  logic [      1:0] sel_i,
    output logic [WIDTH-1:0] out_o [0:SIZE-1]
);

    localparam logic [1:0] GATE_PASS = 2'b00;
    localparam logic [1:0] GATE_ZERO = 2'b01;
    localparam logic [1:0] GATE_NEG  = 2'b10;

    always_comb begin
        for (int i = 0; i < SIZE; i++) begin
            case (sel_i)
                GATE_PASS: out_o[i] = in_i[i];
                GATE_ZERO: out_o[i] = '0;
                GATE_NEG:  out_o[i] = -in_i[i];
                default:   out_o[i] = in_i[i];
            endcase
        end
    end

endmodule
