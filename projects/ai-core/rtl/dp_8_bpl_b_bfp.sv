// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   DP8 (8x4) dot-product core, bit-plane B build. Computes the same
//   sum_{k=0..7}(a_k * b_k) as dp_8 and returns it in carry-save form (sum_o,
//   carry_o), but decomposes the multiplication over the bit planes of b
//   instead of Booth-recoding b. Fixed size - 8 lanes, 8-bit a, 4-bit b.
//
//   Identity, for an unsigned b:
//     sum_k a_k*b_k = sum_h 2^h * sum_j (a_2j * b_2j^h + a_2j+1 * b_2j+1^h)
//   Each inner term is one of {0, a_2j, a_2j+1, a_2j + a_2j+1}, so a lane pair
//   contributes one multiplexer per bit plane, selected by the two lanes' bit h.
//   The pair sums are a function of a alone and arrive precomputed from
//   gate_n_bpl_bfp in the shared per-row dispatch, so their cost is paid once
//   per grid row instead of once per PE.
//
//   This is the dp_8_bpl_a_bfp decomposition with the operand roles exchanged:
//   b indexes the planes and a is tabulated. Because b is the narrower operand
//   there are four planes instead of eight, halving the partial-product count
//   at the cost of a wider multiplexer.
//
//   a_i carries the 9-bit exact signed lane values and a_sum_i the 10-bit pair
//   sums, both already resolved under the dispatcher's is_signed_a, so there is
//   no is_signed_a_i port here. For a signed b the weight-2^3 plane counts
//   negative: its column pair is one's-complemented by comp_n and a single
//   constant 2^4 row completes the two's complement, both gated by is_signed_b_i.
//
//   Reduction: one CPR 4:2 per bit plane, then two CPR 4:2 merging the plane
//   pairs at weights 2^0/2^1, then one CPR 5:2 merging the two nodes at weights
//   2^0/2^2 together with the constant row.
//
//   Widths:
//     stage                          width
//     -----------------------------  -----
//     multiplexer output              10
//     per-plane CPR 4:2 (EXT = 3)     13
//     L1 << 1 CPR 4:2 (EXT = 2)       16
//     L2 CPR 5:2 (EXT = 2)            20
//     output (sign-extended)          22
//
//   The output pair is sign-consistent - signext(sum_o) + signext(carry_o) is
//   the dot product, not just its low bits - which is what lets pe_array_bpl_b_bfp
//   sign-extend and re-align it. The output is padded to 22 bits so the array
//   above keeps the node and tap widths of the bit-plane A build. Combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module dp_8_bpl_b_bfp #(
    localparam int LANES       = 8,
    localparam int IN_WIDTH_A  = 9,
    localparam int SUM_WIDTH   = 10,
    localparam int IN_WIDTH_B  = 4,
    localparam int NUM_BLK     = LANES / 2,
    localparam int NUM_PLANE   = IN_WIDTH_B,
    localparam int MUX_WIDTH   = SUM_WIDTH,
    localparam int MUX_SIZE    = 4,
    localparam int COL_EXT     = 3,
    localparam int COL_WIDTH   = MUX_WIDTH + COL_EXT,
    localparam int NUM_L1      = NUM_PLANE / 2,
    localparam int SH_L1       = 1,
    localparam int L1_IN_WIDTH = COL_WIDTH + SH_L1,
    localparam int L1_EXT      = 2,
    localparam int L1_WIDTH    = L1_IN_WIDTH + L1_EXT,
    localparam int SH_L2       = 2,
    localparam int L2_IN_WIDTH = L1_WIDTH + SH_L2 * (NUM_L1 - 1),
    localparam int L2_IN_SIZE  = 2 * NUM_L1 + 1,
    localparam int L2_EXT      = 2,
    localparam int L2_WIDTH    = L2_IN_WIDTH + L2_EXT,
    localparam int OUT_EXT     = 2,
    localparam int OUT_WIDTH   = L2_WIDTH + OUT_EXT
)(
    input  logic [IN_WIDTH_A-1:0] a_i     [  0:LANES-1],
    input  logic [ SUM_WIDTH-1:0] a_sum_i [0:NUM_BLK-1],
    input  logic [IN_WIDTH_B-1:0] b_i     [  0:LANES-1],
    input  logic                  is_signed_b_i,
    output logic [ OUT_WIDTH-1:0] sum_o,
    output logic [ OUT_WIDTH-1:0] carry_o
);

    logic [  MUX_WIDTH-1:0] a_w       [     0:LANES-1];
    logic [  MUX_WIDTH-1:0] mux_out   [   0:NUM_BLK-1][0:NUM_PLANE-1];
    logic [  COL_WIDTH-1:0] col_sum   [ 0:NUM_PLANE-1];
    logic [  COL_WIDTH-1:0] col_carry [ 0:NUM_PLANE-1];
    logic [  COL_WIDTH-1:0] top_in    [           0:1];
    logic [  COL_WIDTH-1:0] top_out   [           0:1];
    logic [  COL_WIDTH-1:0] col_s     [ 0:NUM_PLANE-1];
    logic [  COL_WIDTH-1:0] col_c     [ 0:NUM_PLANE-1];
    logic [   L1_WIDTH-1:0] l1_sum    [    0:NUM_L1-1];
    logic [   L1_WIDTH-1:0] l1_carry  [    0:NUM_L1-1];
    logic [L2_IN_WIDTH-1:0] l2_in     [0:L2_IN_SIZE-1];
    logic [   L2_WIDTH-1:0] l2_pair   [           0:1];
    logic [  OUT_WIDTH-1:0] out_pair  [           0:1];

    genvar j, h, g;

    ext_n #(
        .WIDTH    (IN_WIDTH_A),
        .SIZE     (LANES),
        .EXT      (MUX_WIDTH-IN_WIDTH_A),
        .IS_SIGNED(1'b1)
    ) ext_n_a_i (
        .in_i (a_i),
        .out_o(a_w)
    );

    generate
        for (j = 0; j < NUM_BLK; j++) begin : gen_blk
            for (h = 0; h < NUM_PLANE; h++) begin : gen_plane
                logic [MUX_WIDTH-1:0] mux_in [0:MUX_SIZE-1];
                logic [          1:0] mux_sel;

                assign mux_in[0] = '0;
                assign mux_in[1] = a_w[2*j+0];
                assign mux_in[2] = a_w[2*j+1];
                assign mux_in[3] = a_sum_i[j];
                assign mux_sel   = {b_i[2*j+1][h], b_i[2*j+0][h]};

                mux_n #(
                    .WIDTH(MUX_WIDTH),
                    .SIZE (MUX_SIZE)
                ) mux_n_i (
                    .in_i (mux_in),
                    .sel_i(mux_sel),
                    .out_o(mux_out[j][h])
                );
            end
        end
    endgenerate

    generate
        for (h = 0; h < NUM_PLANE; h++) begin : gen_col
            logic [MUX_WIDTH-1:0] col [0:NUM_BLK-1];
            for (j = 0; j < NUM_BLK; j++) begin : gen_gather
                assign col[j] = mux_out[j][h];
            end
            cpr_w_n #(
                .IN_WIDTH (MUX_WIDTH),
                .IN_SIZE  (NUM_BLK),
                .EXT      (COL_EXT),
                .IS_SIGNED(1'b1)
            ) cpr_w_n_i (
                .in_i   (col),
                .sum_o  (col_sum[h]),
                .carry_o(col_carry[h])
            );
        end
    endgenerate

    assign top_in[0] = col_sum[NUM_PLANE-1];
    assign top_in[1] = col_carry[NUM_PLANE-1];

    comp_n #(
        .WIDTH(COL_WIDTH),
        .SIZE (2)
    ) comp_n_i (
        .in_i (top_in),
        .neg_i(is_signed_b_i),
        .out_o(top_out)
    );

    generate
        for (h = 0; h < NUM_PLANE-1; h++) begin : gen_pass
            assign col_s[h] = col_sum[h];
            assign col_c[h] = col_carry[h];
        end
    endgenerate

    assign col_s[NUM_PLANE-1] = top_out[0];
    assign col_c[NUM_PLANE-1] = top_out[1];

    generate
        for (g = 0; g < NUM_L1; g++) begin : gen_l1
            logic [L1_IN_WIDTH-1:0] l1_in [0:3];

            assign l1_in[0] = L1_IN_WIDTH'($signed(col_s[2*g+1])) << SH_L1;
            assign l1_in[1] = L1_IN_WIDTH'($signed(col_c[2*g+1])) << SH_L1;
            assign l1_in[2] = L1_IN_WIDTH'($signed(col_s[2*g+0]));
            assign l1_in[3] = L1_IN_WIDTH'($signed(col_c[2*g+0]));

            cpr_w_n #(
                .IN_WIDTH (L1_IN_WIDTH),
                .IN_SIZE  (4),
                .EXT      (L1_EXT),
                .IS_SIGNED(1'b1)
            ) cpr_w_n_i (
                .in_i   (l1_in),
                .sum_o  (l1_sum[g]),
                .carry_o(l1_carry[g])
            );
        end
    endgenerate

    generate
        for (g = 0; g < NUM_L1; g++) begin : gen_l2_align
            assign l2_in[2*g+0] = L2_IN_WIDTH'($signed(l1_sum[g]))   << (SH_L2*g);
            assign l2_in[2*g+1] = L2_IN_WIDTH'($signed(l1_carry[g])) << (SH_L2*g);
        end
    endgenerate

    assign l2_in[L2_IN_SIZE-1] = is_signed_b_i ? L2_IN_WIDTH'(1 << IN_WIDTH_B) : '0;

    cpr_w_n #(
        .IN_WIDTH (L2_IN_WIDTH),
        .IN_SIZE  (L2_IN_SIZE),
        .EXT      (L2_EXT),
        .IS_SIGNED(1'b1)
    ) cpr_w_n_l2_i (
        .in_i   (l2_in),
        .sum_o  (l2_pair[0]),
        .carry_o(l2_pair[1])
    );

    ext_n #(
        .WIDTH    (L2_WIDTH),
        .SIZE     (2),
        .EXT      (OUT_EXT),
        .IS_SIGNED(1'b1)
    ) ext_n_out_i (
        .in_i (l2_pair),
        .out_o(out_pair)
    );

    assign sum_o   = out_pair[0];
    assign carry_o = out_pair[1];

endmodule
