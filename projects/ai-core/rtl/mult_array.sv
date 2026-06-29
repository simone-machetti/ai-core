// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Array of IN_SIZE parallel Booth multipliers, one per (a_i, b_i) input
//   pair. MULT_TYPE selects between Radix-4 (0) and Radix-8 (1) encoding.
//   All multipliers share the same type and signedness. Partial products are
//   laid out in pp_o as:
//     pp_o[i * PP_PER_MUL + j] = j-th partial product of the i-th multiplier.
//
// Parameters:
//   IN_SIZE    - number of parallel multipliers
//   IN_WIDTH_A - bit width of operand A (the encoded multiplier)
//   IN_WIDTH_B - bit width of operand B (the multiplicand)
//   MULT_TYPE  - 0 = Radix-4 Booth, 1 = Radix-8 Booth
//   IS_SIGNED  - 1 = signed operands, 0 = unsigned
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module mult_array #(
    parameter int IN_SIZE    = 64,
    parameter int IN_WIDTH_A = 4,
    parameter int IN_WIDTH_B = 8,
    parameter int MULT_TYPE  = 0,
    parameter bit IS_SIGNED  = 1,

    localparam int RADIX_4    = 0,
    localparam int RADIX_8    = 1,
    localparam int PP_PER_MUL = MULT_TYPE == RADIX_4 ? (IN_WIDTH_A + 1) / 2 : (IN_WIDTH_A + 2) / 3,
    localparam int PP_SIZE    = PP_PER_MUL * IN_SIZE,
    localparam int PP_WIDTH   = MULT_TYPE == RADIX_4 ? IN_WIDTH_B + 2 : IN_WIDTH_B + 3
)(
    input  logic [IN_WIDTH_A-1:0] a_i  [0:IN_SIZE-1],
    input  logic [IN_WIDTH_B-1:0] b_i  [0:IN_SIZE-1],
    output logic [  PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    genvar i, j;
    generate

        for (i = 0; i < IN_SIZE; i++) begin

            logic [PP_WIDTH-1:0] pp [0:PP_PER_MUL-1];

            case (MULT_TYPE)

                RADIX_4: begin : gen_radix_4
                    booth_r4 #(
                        .IN_WIDTH_A(IN_WIDTH_A),
                        .IN_WIDTH_B(IN_WIDTH_B),
                        .IS_SIGNED (IS_SIGNED)
                    ) booth_r4_i (
                        .a_i (a_i[i]),
                        .b_i (b_i[i]),
                        .pp_o(pp)
                    );
                end

                RADIX_8: begin : gen_radix_8
                    booth_r8 #(
                        .IN_WIDTH_A(IN_WIDTH_A),
                        .IN_WIDTH_B(IN_WIDTH_B),
                        .IS_SIGNED (IS_SIGNED)
                    ) booth_r8_i (
                        .a_i (a_i[i]),
                        .b_i (b_i[i]),
                        .pp_o(pp)
                    );
                end

                default: begin : gen_others
                    initial $fatal(1, "mult_array: Unsupported MULT_TYPE=%0d", MULT_TYPE);
                end

            endcase

            for (j = 0; j < PP_PER_MUL; j++)
                assign pp_o[i*PP_PER_MUL+j] = pp[j];

        end

    endgenerate

endmodule
