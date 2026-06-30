// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Array of IN_SIZE elements that either computes a[i]^2 (IS_SQUARE = 1,
//   using sqr_s_4_bit) or passes a[i] through unchanged (IS_SQUARE = 0).
//   All inputs are 4-bit signed. Squared outputs are 8 bits wide; passthrough
//   outputs are 4 bits wide. Used as the partial product generator for
//   top_sqr_4x8_sc_alpha.
//
// Parameters:
//   IN_SIZE   - number of elements
//   IS_SQUARE - 1 = compute a[i]^2; 0 = passthrough
// -----------------------------------------------------------------------------

/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module sqr_s_4_bit_alpha_array #(
    parameter int IN_SIZE   = 8,
    parameter bit IS_SQUARE = 0,

    localparam int IN_WIDTH = 4,
    localparam int PP_SIZE  = IN_SIZE,
    localparam int PP_WIDTH = IS_SQUARE ? (2 * IN_WIDTH) : IN_WIDTH
)(
    input  logic [IN_WIDTH-1:0] a_i  [0:IN_SIZE-1],
    output logic [PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    genvar i;
    generate

        for (i = 0; i < IN_SIZE; i++) begin : gen_loop

            if (IS_SQUARE) begin : gen_sqr

                sqr_s_4_bit sqr_s_4_bit_i (
                    .in_i (a_i[i]),
                    .out_o(pp_o[i])
                );

            end else begin : gen_prop

                assign pp_o[i] = a_i[i];

            end

        end

    endgenerate

endmodule
