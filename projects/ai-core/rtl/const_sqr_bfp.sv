// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Per-DP8 constants for the square-BFP datapath - the const_sqr analogue for
//   pe_array_sqr_bfp. Where const_sqr folds every square-reconstruction deferral
//   into ONE tree-summed constant that the accumulator adds, the BFP square
//   combines PE - alpha - beta + C per DP8 AT L0 (under each block's own scale),
//   so the constant is needed per DP8, not per output lane. This is that LUT: a
//   small combinational table addressed by the 4-bit mode, emitting one 18-bit
//   signed constant for each of the 16 DP8s.
//
//   Per-DP8 fold (const_dp8 = the signed value L0 ADDS to that block):
//     + C_cent : the excess-centering constant, per DP8 from its own signedness
//                C_cent = 16*c(nAH) + c(nAL),  nAH = ~is_signed_a + ~is_signed_b,
//                nAL = 1 + ~is_signed_b,  c(0/1/2) = 0/512/2048.
//     + 4      : the two tree-less generators each emit -alpha/-beta by one's-
//                complement, deferring -2 apiece (-value-2) -> +4 per DP8.
//     block-negate (modes 10/11): the DP8s whose lo bundle pe_array_sqr_bfp
//                one's-complements (neg mapping -> DP8 2,3,6,7,10,11) instead add
//                2 - C_cent, so after the block flips sign the constant lands
//                correct. Real modes / non-negated DP8s add C_cent + 4.
//
//     const_dp8 = negated ? (2 - C_cent) : (C_cent + 4)
//
//   The is_signed_a/b and neg patterns per mode are exactly ctrl_sqr's decode, so
//   the table is precomputed here (like const_sqr's hardcoded constants) rather
//   than re-deriving them from decoded signals. Idle DP8s (ctrl_sqr zero_o) have
//   their constant gated to 0 inside pe_array_sqr_bfp, so their table entry is a
//   don't-care (left at +4). Invalid mode addresses return 0 on every DP8.
//
//   Pipeline: none here. In the grid the mode is registered once ahead of this
//   LUT so the constant meets the singly-registered dispatched operands at the L0
//   combine, where pe_array_sqr_bfp's L0 register captures the whole bundle - one
//   register fewer than const_sqr (which must reach the later acc stage).
//
// Local parameters (fixed - the mode addresses and constants are hardcoded):
//   MODE_WIDTH - mode address width (4)
//   NUM_DP8    - number of DP8 blocks (16)
//   DP8_WIDTH  - per-DP8 constant width (18, signed; holds -10238..+34820)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module const_sqr_bfp #(
    localparam int MODE_WIDTH = 4,
    localparam int NUM_DP8    = 16,
    localparam int DP8_WIDTH  = 18
)(
    input  logic [MODE_WIDTH-1:0] mode_i,
    output logic [ DP8_WIDTH-1:0] const_dp8_o [0:NUM_DP8-1]
);

    always_comb begin
        unique case (mode_i)
            4'd1:  const_dp8_o = '{18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516, 18'sd516};
            4'd2:  const_dp8_o = '{18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244};
            4'd3:  const_dp8_o = '{18'sd516, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd516, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd516, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd516, 18'sd10244, 18'sd8708, 18'sd34820};
            4'd5:  const_dp8_o = '{18'sd516, 18'sd4, 18'sd516, 18'sd4, 18'sd516, 18'sd4, 18'sd516, 18'sd4, 18'sd4, 18'sd516, 18'sd4, 18'sd516, 18'sd4, 18'sd516, 18'sd4, 18'sd516};
            4'd6:  const_dp8_o = '{18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd4, 18'sd4, 18'sd4, 18'sd4, 18'sd4, 18'sd4, 18'sd4, 18'sd4};
            4'd7:  const_dp8_o = '{18'sd516, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd516, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd516, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd516, 18'sd10244, 18'sd8708, 18'sd34820};
            4'd8:  const_dp8_o = '{18'sd516, 18'sd10244, 18'sd10244, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd34820, 18'sd34820, 18'sd516, 18'sd10244, 18'sd10244, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd34820, 18'sd34820};
            4'd9:  const_dp8_o = '{18'sd516, 18'sd10244, 18'sd10244, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd34820, 18'sd34820, 18'sd516, 18'sd10244, 18'sd10244, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd34820, 18'sd34820};
            4'd10: const_dp8_o = '{18'sd516, 18'sd10244, -18'sd510, -18'sd10238, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, -18'sd510, -18'sd10238, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244};
            4'd11: const_dp8_o = '{18'sd516, 18'sd10244, -18'sd510, -18'sd10238, 18'sd516, 18'sd10244, -18'sd510, -18'sd10238, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244, 18'sd516, 18'sd10244};
            4'd12: const_dp8_o = '{18'sd516, 18'sd10244, 18'sd10244, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd34820, 18'sd34820, 18'sd516, 18'sd10244, 18'sd10244, 18'sd10244, 18'sd8708, 18'sd34820, 18'sd34820, 18'sd34820};
            default: const_dp8_o = '{default: '0};
        endcase
    end

endmodule
