// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Radix-4 Booth multiplier partial-product generator with per-operand runtime
//   signedness. Recodes the multiplier b_i into PP_SIZE = IN_WIDTH_B/2 + 1
//   overlapping 3-bit selectors and drives one booth_r4_cell per selector to
//   produce the partial products from multiplicand a_i (each PP_WIDTH =
//   IN_WIDTH_A + 2 bits). Booth-encoding the operand with the fewest bits
//   minimizes the partial-product count, so b_i should carry the narrower operand
//   (e.g. the 4-bit operand of an 8x4 multiply).
//
//   Signedness is per operand and runtime:
//     - is_signed_a_i selects how the multiplicand a_i is extended in each cell
//       (sign vs zero) when forming +-a / +-2a.
//     - is_signed_b_i selects how the multiplier b_i is extended above its MSB
//       (sign vs zero) before recoding. The extra top digit (weight 4^(PP_SIZE-1))
//       is what distinguishes the two: for a SIGNED b it recodes to 0 (the sign is
//       already carried by the next-lower digit), so the top partial product
//       vanishes; for an UNSIGNED b it emits a final {0,+a} partial product that
//       supplies the missing positive weight of the top bit. PP_SIZE therefore
//       carries the count needed for the unsigned case.
//
// Parameters:
//   IN_WIDTH_A - bit width of the multiplicand (a_i)
//   IN_WIDTH_B - bit width of the multiplier (b_i, recoded; the narrower operand)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module booth_r4 #(
    parameter int IN_WIDTH_A = 8,
    parameter int IN_WIDTH_B = 4,

    localparam int PP_SIZE  = IN_WIDTH_B / 2 + 1,
    localparam int PP_WIDTH = IN_WIDTH_A + 2
)(
    input  logic [IN_WIDTH_A-1:0] a_i,
    input  logic [IN_WIDTH_B-1:0] b_i,
    input  logic                  is_signed_a_i,
    input  logic                  is_signed_b_i,
    output logic [  PP_WIDTH-1:0] pp_o [0:PP_SIZE-1]
);

    localparam int MULT_EXT_WIDTH = 2 * PP_SIZE + 1;

    logic                      ext_bit;
    logic [MULT_EXT_WIDTH-1:0] mult_ext;

    assign ext_bit  = is_signed_b_i ? b_i[IN_WIDTH_B-1] : 1'b0;
    assign mult_ext = {{(MULT_EXT_WIDTH-IN_WIDTH_B-1){ext_bit}}, b_i, 1'b0};

    genvar i;
    generate
        for (i = 0; i < PP_SIZE; i++) begin : gen_booth
            logic [2:0] sel;
            assign sel = mult_ext[2*i +: 3];
            booth_r4_cell #(
                .IN_WIDTH(IN_WIDTH_A)
            ) booth_r4_cell_i (
                .mult_i     (a_i),
                .sel_i      (sel),
                .is_signed_i(is_signed_a_i),
                .pp_o       (pp_o[i])
            );
        end
    endgenerate

endmodule
