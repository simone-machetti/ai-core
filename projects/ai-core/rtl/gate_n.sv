// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized zero gate. For each of SIZE input words, WIDTH bits wide,
//   passes the input through when sel_i is 0 or forces it to zero when sel_i
//   is 1. The select is shared by all words. Used for operand masking (e.g. the
//   operand-A path, which only ever needs masking to zero, never negation) and,
//   at WIDTH = 1, as a carry enable - it gates the inter-lane carry chain in
//   acc_array (drive sel_i = ~prop_carry to pass the carry only when fusing).
//
// Parameters:
//   WIDTH - bit width of each word
//   SIZE  - number of words (all share the select)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module gate_n #(
    parameter int WIDTH = 8,
    parameter int SIZE  = 4
)(
    input  logic [WIDTH-1:0] in_i  [0:SIZE-1],
    input  logic             sel_i,
    output logic [WIDTH-1:0] out_o [0:SIZE-1]
);

    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_gate
            assign out_o[i] = sel_i ? '0 : in_i[i];
        end
    endgenerate

endmodule
