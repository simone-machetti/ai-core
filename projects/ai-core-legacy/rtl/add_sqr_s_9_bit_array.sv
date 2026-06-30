// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Array of IN_SIZE squaring units. Each unit computes pp[i] = (a[i]+b[i])^2
//   using sqr_s_9_bit on the sign-extended 9-bit sum. Both a_i and b_i are
//   8-bit signed inputs. Output partial products are PP_WIDTH = 18 bits wide.
//   Used by top_sqr_8x8 to implement the squaring-based multiply-accumulate.
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module add_sqr_s_9_bit_array #(
    parameter int IN_SIZE = 32,

    localparam int IN_WIDTH      = 8,
    localparam int IN_SQR_WIDTH  = IN_WIDTH + 1,
    localparam int OUT_SQR_WIDTH = (IN_SQR_WIDTH * 2) - 1,
    localparam int PP_SIZE       = IN_SIZE,
    localparam int PP_WIDTH      = OUT_SQR_WIDTH + 1
)(
    input  logic [IN_WIDTH-1:0] a_i  [0:IN_SIZE-1],
    input  logic [IN_WIDTH-1:0] b_i  [0:IN_SIZE-1],
    output logic [PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    genvar i;
    generate

        for (i = 0; i < IN_SIZE; i++) begin : gen_sqr

            logic signed [ IN_SQR_WIDTH-1:0] sum;
            logic        [OUT_SQR_WIDTH-1:0] pp;

            assign sum = IN_SQR_WIDTH'($signed(a_i[i])) + IN_SQR_WIDTH'($signed(b_i[i]));

            sqr_s_9_bit sqr_s_9_bit_i (
                .in_i (sum),
                .out_o(pp)
            );

            assign pp_o[i] = {1'b0, pp};

        end

    endgenerate

endmodule
