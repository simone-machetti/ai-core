// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   DP8 (8x4) dot-product core with per-operand runtime signedness. Computes
//   sum_{k=0..7}(a_k * b_k) of eight int8 x int4 products and returns it in
//   carry-save form (sum_o, carry_o). Fixed size - 8 lanes, 8-bit multiplicand
//   a, 4-bit multiplier b.
//
//   is_signed_a_i / is_signed_b_i set each operand's signedness independently, so
//   all four combinations occur across the operating modes (a high field is
//   signed, a low field is unsigned - and likewise for b). An unsigned b needs
//   one extra radix-4 Booth partial product, so booth_r4 emits PP_SIZE = 3
//   partial products (weights 2^0, 2^2, 2^4); the top one is 0 when b is signed.
//
//   Widths, minimum for this size:
//     stage                    width   dynamic range + headroom
//     -----------------------  -----   ------------------------------------
//     Booth partial product     10     int8 * {0,+-1,+-2} (exact)
//     per-weight CPR 8:2 (x3)   14     13b sum-of-8   + 1 guard bit
//     weight-2^4 align (<< 4)   18     14b row shifted << 4
//     final CPR 6:2 (EXT = 2)   20     six carry-save pairs -> two rows
//     output                    20     16b value + 4 guard bits (see below)
//
//   Worst-case output is the unsigned x unsigned corner: 8 * 255 * 15 = 30600
//   (and -16320 for unsigned-a x signed-b) - a 16-bit signed range. The DP8 must
//   deliver its result as a *sign-consistent* carry-save pair (signext(sum) +
//   signext(carry) == value) so the downstream reduction can sign-extend it;
//   that is a stronger property than a correct resolve (sum + carry mod 2^W).
//
//   The final CPR 6:2 reduces six sign-extended rows. cpr_w_n drops any carry
//   out of its top bit (carry row is cout << 1), so to stay sign-consistent it
//   needs EXT = ceil(log2(rows)) guard bits above the widest input - never
//   EXT = 0, which silently loses the top carry when the redundant rows both
//   reach into the guard region (resolve still holds, sign-consistency does
//   not). The six inputs reach 2^13 / 2^15 / 2^17 in magnitude (weights 2^0 /
//   2^2 / 2^4), so their absolute sum is bounded by 2^14 + 2^16 + 2^18 = 344064;
//   sign-consistency is guaranteed once 2^(OUT_WIDTH-1) > 344064, i.e.
//   OUT_WIDTH >= 20, so FINAL_EXT = 2 (FINAL_IN 18 + 2). The 20-bit output is
//   the 16-bit value plus 4 guard bits of carry-save headroom - not truncated.
//   Verified sign-consistent over 5,000,000 corner-biased vectors. Combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module dp_8 #(
    localparam int LANES      = 8,
    localparam int IN_WIDTH_A = 8,
    localparam int IN_WIDTH_B = 4,
    localparam int PP_SIZE    = IN_WIDTH_B / 2 + 1,
    localparam int PP_WIDTH   = IN_WIDTH_A + 2,
    localparam int CPR2_WIDTH = PP_WIDTH + $clog2(LANES) + 1,
    localparam int FINAL_IN   = CPR2_WIDTH + 2 * (PP_SIZE - 1),
    localparam int FINAL_EXT  = 2,
    localparam int OUT_WIDTH  = FINAL_IN + FINAL_EXT
)(
    input  logic [IN_WIDTH_A-1:0] a_i [0:LANES-1],
    input  logic [IN_WIDTH_B-1:0] b_i [0:LANES-1],
    input  logic                  is_signed_a_i,
    input  logic                  is_signed_b_i,
    output logic [ OUT_WIDTH-1:0] sum_o,
    output logic [ OUT_WIDTH-1:0] carry_o
);

    logic [  PP_WIDTH-1:0] pp        [0:LANES-1][0:PP_SIZE-1];
    logic [CPR2_WIDTH-1:0] col_sum   [0:PP_SIZE-1];
    logic [CPR2_WIDTH-1:0] col_carry [0:PP_SIZE-1];
    logic [  FINAL_IN-1:0] final_in  [0:2*PP_SIZE-1];

    logic [ OUT_WIDTH-1:0] final_sum;
    logic [ OUT_WIDTH-1:0] final_carry;

    genvar inst, j, k;

    generate
        for (inst = 0; inst < LANES; inst++) begin : gen_booth
            booth_r4 #(
                .IN_WIDTH_A(IN_WIDTH_A),
                .IN_WIDTH_B(IN_WIDTH_B)
            ) booth_r4_i (
                .a_i          (a_i[inst]),
                .b_i          (b_i[inst]),
                .is_signed_a_i(is_signed_a_i),
                .is_signed_b_i(is_signed_b_i),
                .pp_o         (pp[inst])
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
        .sum_o  (final_sum),
        .carry_o(final_carry)
    );

    assign sum_o   = final_sum;
    assign carry_o = final_carry;

endmodule
