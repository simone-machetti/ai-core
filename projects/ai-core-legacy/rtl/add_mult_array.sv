// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Winograd-style partial product generator for paired inputs. Processes
//   input pairs (i, i+1) and computes, for each pair:
//     sum_0 = a[i+1] + b[i]
//     sum_1 = a[i]   + b[i+1]
//     pp    = Booth(sum_0, sum_1)   [PP_PER_MUL partial products]
//   This exploits the identity (a+b)*(c+d) = ... to implement Winograd-style
//   convolution, halving the multiplier count relative to baseline.
//   Total output: PP_SIZE = PP_PER_MUL * IN_SIZE / 2 partial products.
//
// Parameters:
//   IN_SIZE    - total number of inputs (must be even)
//   IN_WIDTH_A - bit width of operands in the A array
//   IN_WIDTH_B - bit width of operands in the B array
//   MULT_TYPE  - 0 = Radix-4 Booth, 1 = Radix-8 Booth
//   IS_SIGNED  - 1 = signed inputs, 0 = unsigned
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module add_mult_array #(
    parameter int IN_SIZE    = 64,
    parameter int IN_WIDTH_A = 4,
    parameter int IN_WIDTH_B = 8,
    parameter int MULT_TYPE  = 0,
    parameter bit IS_SIGNED  = 1,

    localparam int RADIX_4      = 0,
    localparam int RADIX_8      = 1,
    localparam int IN_MUL_WIDTH = IN_WIDTH_B + 2,
    localparam int PP_PER_MUL   = MULT_TYPE == RADIX_4 ? (IN_MUL_WIDTH + 1) / 2 : (IN_MUL_WIDTH + 2) / 3,
    localparam int PP_SIZE      = PP_PER_MUL * IN_SIZE / 2,
    localparam int PP_WIDTH     = MULT_TYPE == RADIX_4 ? IN_MUL_WIDTH + 2 : IN_MUL_WIDTH + 3
)(
    input  logic [IN_WIDTH_A-1:0] a_i  [0:IN_SIZE-1],
    input  logic [IN_WIDTH_B-1:0] b_i  [0:IN_SIZE-1],
    output logic [  PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    genvar i, j;
    generate

        for (i = 0; i < IN_SIZE; i = i + 2) begin : gen_mul

            logic signed [IN_MUL_WIDTH-1:0] sum_0;
            logic signed [IN_MUL_WIDTH-1:0] sum_1;

            logic [PP_WIDTH-1:0] pp [0:PP_PER_MUL-1];

            if (IS_SIGNED == 0) begin : gen_unsigned

                always_comb begin
                    sum_0 = IN_MUL_WIDTH'($signed(a_i[i+1])) + IN_MUL_WIDTH'($unsigned(b_i[i]));
                    sum_1 = IN_MUL_WIDTH'($signed(a_i[i]))   + IN_MUL_WIDTH'($unsigned(b_i[i+1]));
                end

            end else begin : gen_signed

                always_comb begin
                    sum_0 = IN_MUL_WIDTH'($signed(a_i[i+1])) + IN_MUL_WIDTH'($signed(b_i[i]));
                    sum_1 = IN_MUL_WIDTH'($signed(a_i[i]))   + IN_MUL_WIDTH'($signed(b_i[i+1]));
                end

            end

            case (MULT_TYPE)

                RADIX_4: begin : gen_radix_4
                    booth_r4 #(
                        .IN_WIDTH_A(IN_MUL_WIDTH),
                        .IN_WIDTH_B(IN_MUL_WIDTH),
                        .IS_SIGNED (1)
                    ) booth_r4_i (
                        .a_i (sum_0),
                        .b_i (sum_1),
                        .pp_o(pp)
                    );
                end

                RADIX_8: begin : gen_radix_8
                    booth_r8 #(
                        .IN_WIDTH_A(IN_MUL_WIDTH),
                        .IN_WIDTH_B(IN_MUL_WIDTH),
                        .IS_SIGNED (1)
                    ) booth_r8_i (
                        .a_i (sum_0),
                        .b_i (sum_1),
                        .pp_o(pp)
                    );
                end

                default: begin : gen_others
                    initial $fatal(1, "add_mult_array: Unsupported MULT_TYPE=%0d", MULT_TYPE);
                end

            endcase

            for (j = 0; j < PP_PER_MUL; j++)
                assign pp_o[(i/2)*PP_PER_MUL+j] = pp[j];

        end

    endgenerate

endmodule
