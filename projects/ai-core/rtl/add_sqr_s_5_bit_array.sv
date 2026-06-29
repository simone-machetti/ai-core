// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Array of IN_SIZE squaring units. Each unit computes pp[i] = (a[i]+b[i])^2
//   on the sign-extended 5-bit sum. Both a_i and b_i are 4-bit signed inputs.
//   Output partial products are PP_WIDTH = 10 bits wide.
//   SQR_TYPE selects the squarer implementation: 0 = sqr_s_5_bit_v0 (structural,
//   ripple HA chain), 1 = sqr_s_5_bit_v1 (flat KMap-minimized Boolean).
//   Used by sqr_4x8_sc to implement the squaring-based multiply-accumulate.
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module add_sqr_s_5_bit_array #(
    parameter int IN_SIZE   = 8,
    parameter int SQR_TYPE  = 0,

    localparam int IN_WIDTH      = 4,
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

            if (SQR_TYPE == 0) begin : gen_v0
                sqr_s_5_bit_v0 sqr_s_5_bit_i (
                    .in_i (sum),
                    .out_o(pp)
                );
            end else begin : gen_v1
                sqr_s_5_bit_v1 sqr_s_5_bit_i (
                    .in_i (sum),
                    .out_o(pp)
                );
            end

            assign pp_o[i] = {1'b0, pp};

        end

    endgenerate

endmodule
