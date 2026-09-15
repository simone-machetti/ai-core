// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   DP8 (8x4) dot-product core with TWO partial products per lane, built on the
//   hybrid NR4SD+/Booth recoding of B. Computes the same sum_{k=0..7}(a_k * b_k)
//   as dp_8 and returns it in the same 20-bit sign-consistent carry-save form, so
//   it is a drop-in leaf for the BFP reduction tree.
//
//   The multiplier is NOT recoded here. b arrives already recoded from
//   disp_array_b_nr4sd_bfp, which owns the recoders (nr4sd_r4) and amortizes them
//   over the whole column, as two digit codes per lane:
//
//     b_nr4sd_i[k]  2-bit NR4SD+ code, digit at weight 1   -> nr4sd_r4_cell
//                   00 -> 0     01 -> +A    10 -> +2A    11 -> -A
//     b_booth_i[k]  3-bit Booth window, digit at weight 4  -> booth_r4_cell
//                   {0, +A, +2A, -A, -2A}
//
//   so the lane value is digit_0 + 4*digit_1 in [-9, +10]: the nibble read as
//   SIGNED plus the cross-nibble carry the dispatcher injects (see nr4sd_r4). A
//   DP8 holding a LOWER nibble of a wider element therefore returns a partial that
//   is 16*b3*A too small per lane and is NOT a value on its own; the DP8 holding
//   the nibble above carries the matching +b3*A, and the tree's x16 weight cancels
//   the two. Every mode reads its tap after that merge. There is no is_signed_b_i
//   port; is_signed_a_i remains and is the ONLY signedness signal in the DP8.
//
//   Against dp_8 / the 3-digit NR4SD+ build, the third partial product (the
//   correction digit for unsigned nibbles) is gone: 16 cells instead of 24, two
//   per-weight compressors instead of three, a 4:2 final stage instead of 6:2 -
//   204 full adders instead of 332. The -2A multiple lives in the Booth cell only.
//
//   Widths - the digit set still tops out at |2|, so a partial product spans
//   [-256, +254] (signed a) or [-255, +510] (unsigned a), inside 10-bit signed:
//
//     stage                    width   dynamic range + headroom
//     -----------------------  -----   ------------------------------------
//     partial product           10     int8 * {-2..+2} (exact)
//     per-weight CPR 8:2 (x2)   14     13b sum-of-8   + 1 guard bit
//     weight-4 align (<< 2)     16     14b row shifted << 2
//     final CPR 4:2 (EXT = 2)   18     four carry-save rows -> two rows
//     output (sign-extended)    20     kept at dp_8's width, wires only
//
//   The output pair is sign-consistent (signext(sum) + signext(carry) == value),
//   the stronger property the tree above depends on when it sign-extends and
//   re-aligns. Rows reach 2^13 / 2^15, so the absolute sum is under 2^14 + 2^16 and
//   FINAL_EXT = 2 keeps 2^(FINAL_WIDTH-1) above it; the ext_n to 20 bits preserves
//   the property (sign-extending both rows of a sign-consistent pair leaves their
//   sum unchanged) and lets pe_array_nr4sd_bfp keep baseline-BFP's node and tap
//   widths, so acc_array_bfp is reused unchanged. Combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module dp_8_nr4sd_bfp #(
    localparam int LANES       = 8,
    localparam int IN_WIDTH_A  = 8,
    localparam int IN_WIDTH_B  = 4,
    localparam int NUM_DIGIT   = IN_WIDTH_B / 2,
    localparam int CODE_WIDTH  = 2,
    localparam int SEL_WIDTH   = 3,
    localparam int PP_SIZE     = NUM_DIGIT,
    localparam int PP_WIDTH    = IN_WIDTH_A + 2,
    localparam int CPR2_WIDTH  = PP_WIDTH + $clog2(LANES) + 1,
    localparam int FINAL_IN    = CPR2_WIDTH + 2 * (PP_SIZE - 1),
    localparam int FINAL_EXT   = 2,
    localparam int FINAL_WIDTH = FINAL_IN + FINAL_EXT,
    localparam int OUT_EXT     = 2,
    localparam int OUT_WIDTH   = FINAL_WIDTH + OUT_EXT
)(
    input  logic [IN_WIDTH_A-1:0] a_i       [0:LANES-1],
    input  logic [CODE_WIDTH-1:0] b_nr4sd_i [0:LANES-1],
    input  logic [ SEL_WIDTH-1:0] b_booth_i [0:LANES-1],
    input  logic                  is_signed_a_i,
    output logic [ OUT_WIDTH-1:0] sum_o,
    output logic [ OUT_WIDTH-1:0] carry_o
);

    logic [   PP_WIDTH-1:0] pp         [0:LANES-1][0:PP_SIZE-1];
    logic [ CPR2_WIDTH-1:0] col_sum    [0:PP_SIZE-1];
    logic [ CPR2_WIDTH-1:0] col_carry  [0:PP_SIZE-1];
    logic [   FINAL_IN-1:0] final_in   [0:2*PP_SIZE-1];
    logic [FINAL_WIDTH-1:0] final_pair [0:1];
    logic [  OUT_WIDTH-1:0] out_pair   [0:1];

    genvar inst, j, k;

    generate
        for (inst = 0; inst < LANES; inst++) begin : gen_lane
            nr4sd_r4_cell #(
                .IN_WIDTH(IN_WIDTH_A)
            ) nr4sd_r4_cell_i (
                .mult_i     (a_i[inst]),
                .code_i     (b_nr4sd_i[inst]),
                .is_signed_i(is_signed_a_i),
                .pp_o       (pp[inst][0])
            );
            booth_r4_cell #(
                .IN_WIDTH(IN_WIDTH_A)
            ) booth_r4_cell_i (
                .mult_i     (a_i[inst]),
                .sel_i      (b_booth_i[inst]),
                .is_signed_i(is_signed_a_i),
                .pp_o       (pp[inst][1])
            );
        end
    endgenerate

    generate
        for (j = 0; j < PP_SIZE; j++) begin : gen_weight
            logic [PP_WIDTH-1:0] col [0:LANES-1];
            for (k = 0; k < LANES; k++) begin : gen_gather
                assign col[k] = pp[k][j];
            end
            cpr_w_n #(
                .IN_WIDTH (PP_WIDTH),
                .IN_SIZE  (LANES),
                .EXT      ($clog2(LANES) + 1),
                .IS_SIGNED(1'b1)
            ) cpr_w_n_i (
                .in_i   (col),
                .sum_o  (col_sum[j]),
                .carry_o(col_carry[j])
            );
            assign final_in[2*j+0] = FINAL_IN'($signed(col_sum[j]))   << (2*j);
            assign final_in[2*j+1] = FINAL_IN'($signed(col_carry[j])) << (2*j);
        end
    endgenerate

    cpr_w_n #(
        .IN_WIDTH (FINAL_IN),
        .IN_SIZE  (2*PP_SIZE),
        .EXT      (FINAL_EXT),
        .IS_SIGNED(1'b1)
    ) cpr_w_n_final_i (
        .in_i   (final_in),
        .sum_o  (final_pair[0]),
        .carry_o(final_pair[1])
    );

    ext_n #(
        .WIDTH    (FINAL_WIDTH),
        .SIZE     (2),
        .EXT      (OUT_EXT),
        .IS_SIGNED(1'b1)
    ) ext_n_out_i (
        .in_i (final_pair),
        .out_o(out_pair)
    );

    assign sum_o   = out_pair[0];
    assign carry_o = out_pair[1];

endmodule
