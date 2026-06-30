// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Radix-4 Booth multiplier. Sign-extends operand A by one bit, appends a
//   leading zero, then extracts PP_SIZE = (IN_WIDTH_A + 1) / 2 overlapping
//   3-bit selectors. Each selector drives a booth_r4_cell to generate one
//   partial product from multiplicand B. All partial products are
//   (IN_WIDTH_B + 2) bits wide.
//
// Parameters:
//   IN_WIDTH_A - bit width of the multiplier (A, encoded into selectors)
//   IN_WIDTH_B - bit width of the multiplicand (B)
//   IS_SIGNED  - 1 = signed operands, 0 = unsigned
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module booth_r4 #(
    parameter int IN_WIDTH_A = 4,
    parameter int IN_WIDTH_B = 8,
    parameter bit IS_SIGNED  = 1,

    localparam int PP_SIZE  = (IN_WIDTH_A + 1) / 2,
    localparam int PP_WIDTH = IN_WIDTH_B + 2
)(
    input  logic [IN_WIDTH_A-1:0] a_i,
    input  logic [IN_WIDTH_B-1:0] b_i,
    output logic [  PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    localparam int MULT_EXT_WIDTH = 2 * PP_SIZE + 1;

    logic [MULT_EXT_WIDTH-1:0] mult_ext;

    assign mult_ext = {{(MULT_EXT_WIDTH-IN_WIDTH_A-1){a_i[IN_WIDTH_A-1]}}, a_i, 1'b0};

    genvar i;
    generate

        for (i = 0; i < PP_SIZE; i++) begin : gen_booth

            logic [2:0] sel;

            assign sel = mult_ext[2*i +: 3];

            booth_r4_cell #(
                .IN_WIDTH (IN_WIDTH_B),
                .IS_SIGNED(IS_SIGNED)
            ) booth_r4_cell_i (
                .mult_i(b_i),
                .sel_i (sel),
                .pp_o  (pp_o[i])
            );

        end

    endgenerate

endmodule
