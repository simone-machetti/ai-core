// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Conditional sign/zero extension with optional left shift for an array
//   of IN_SIZE values. Controlled at runtime by is_signed_i and is_shift_i:
//     - is_signed_i = 1: sign-extend; 0: zero-extend by EXTEND bits.
//     - is_shift_i  = 1: left-shift the original value into the upper bits
//                        after extension (equivalent to multiplying by 2^EXTEND).
//   Used by cpr_tree to align compression-tree outputs before each stage.
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module ext_n #(
    parameter int IN_SIZE  = 2,
    parameter int IN_WIDTH = 8,
    parameter int EXTEND   = 4
)(
    input  logic                       is_signed_i,
    input  logic                       is_shift_i,
    input  logic [       IN_WIDTH-1:0] in_i  [0:IN_SIZE-1],
    output logic [IN_WIDTH+EXTEND-1:0] out_o [0:IN_SIZE-1]
);

    logic [IN_WIDTH+EXTEND-1:0] tmp [0:IN_SIZE-1];

    genvar i;
    generate
        for (i = 0; i < IN_SIZE; i++) begin : gen_extend
            assign tmp[i] = is_signed_i == 1'b1 ? {{EXTEND{in_i[i][IN_WIDTH-1]}}, in_i[i]} : {{EXTEND{1'b0}}, in_i[i]};
        end
    endgenerate

    generate
        for (i = 0; i < IN_SIZE; i++) begin : gen_shift
            assign out_o[i] = is_shift_i == 1'b1 ? {tmp[i][IN_WIDTH-1:0], {EXTEND{1'b0}}} : tmp[i];
        end
    endgenerate

endmodule
