// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Signed multiplier that wraps either a Radix-4 or Radix-8 Booth partial
//   product generator (selected by MULT_TYPE) and finalises the product by
//   sign-extending each partial product to OUT_WIDTH bits, shifting it left
//   by STRIDE*i positions (STRIDE = 2 for R4, 3 for R8), and summing all
//   partial products combinationally.
//
// Parameters:
//   IN_WIDTH_A - bit width of operand A (the Booth-encoded multiplier)
//   IN_WIDTH_B - bit width of operand B (the multiplicand)
//   MULT_TYPE  - 0 = Radix-4 Booth (stride 2), 1 = Radix-8 Booth (stride 3)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module mul_s #(
    parameter int IN_WIDTH_A = 8,
    parameter int IN_WIDTH_B = 8,
    parameter int MULT_TYPE  = 0,

    localparam int OUT_WIDTH = IN_WIDTH_A + IN_WIDTH_B
)(
    input  logic [IN_WIDTH_A-1:0] a_i,
    input  logic [IN_WIDTH_B-1:0] b_i,
    output logic [ OUT_WIDTH-1:0] out_o
);

    localparam int RADIX_4  = 0;
    localparam int RADIX_8  = 1;
    localparam int PP_SIZE  = MULT_TYPE == RADIX_4 ? (IN_WIDTH_A + 1) / 2 : (IN_WIDTH_A + 2) / 3;
    localparam int PP_WIDTH = MULT_TYPE == RADIX_4 ? IN_WIDTH_B + 2 : IN_WIDTH_B + 3;
    localparam int STRIDE   = MULT_TYPE == RADIX_4 ? 2 : 3;

    logic [PP_WIDTH-1:0] pp [0:PP_SIZE-1];

    generate
        case (MULT_TYPE)

            RADIX_4: begin : gen_booth_r4
                booth_r4 #(
                    .IN_WIDTH_A(IN_WIDTH_A),
                    .IN_WIDTH_B(IN_WIDTH_B),
                    .IS_SIGNED (1)
                ) booth_r4_i (
                    .a_i (a_i),
                    .b_i (b_i),
                    .pp_o(pp)
                );
            end

            RADIX_8: begin : gen_booth_r8
                booth_r8 #(
                    .IN_WIDTH_A(IN_WIDTH_A),
                    .IN_WIDTH_B(IN_WIDTH_B),
                    .IS_SIGNED (1)
                ) booth_r8_i (
                    .a_i (a_i),
                    .b_i (b_i),
                    .pp_o(pp)
                );
            end

            default: begin : gen_others
                initial $fatal(1, "mul_s: Unsupported MULT_TYPE=%0d", MULT_TYPE);
            end

        endcase
    endgenerate

    logic signed [OUT_WIDTH-1:0] pp_shifted [0:PP_SIZE-1];

    genvar i;
    generate
        for (i = 0; i < PP_SIZE; i++) begin : gen_shift
            assign pp_shifted[i] = OUT_WIDTH'(signed'(pp[i])) << (STRIDE * i);
        end
    endgenerate

    always_comb begin
        out_o = '0;
        for (int j = 0; j < PP_SIZE; j++)
            out_o = out_o + pp_shifted[j];
    end

endmodule
