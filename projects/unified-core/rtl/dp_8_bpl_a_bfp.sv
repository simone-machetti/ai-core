// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   DP8 (8x4) dot-product core, bit-plane build. Computes the same
//   sum_{k=0..7}(a_k * b_k) as dp_8 and returns it in carry-save form (sum_o,
//   carry_o), but decomposes the multiplication over the bit planes of a instead
//   of Booth-recoding b. Fixed size - 8 lanes, 8-bit a, 4-bit b.
//
//   Identity, for an unsigned a:
//     sum_k a_k*b_k = sum_h 2^h * sum_j (a_2j^h * b_2j + a_2j+1^h * b_2j+1)
//   Each inner term is one of {0, b_2j, b_2j+1, b_2j + b_2j+1}, so a lane pair
//   contributes one multiplexer per bit plane, selected by the two lanes' bit h.
//   The pair sums are a function of b alone and arrive precomputed from
//   gate_n_bpl_bfp in the shared per-column dispatch, so their cost is paid
//   once per grid column instead of once per PE.
//
//   b_i carries the 5-bit exact signed lane values and b_sum_i the 6-bit pair
//   sums, both already resolved under the dispatcher's is_signed_b, so there is
//   no is_signed_b_i port here. For a signed a the weight-2^7 plane counts
//   negative: its column pair is one's-complemented by comp_n and a single
//   constant 2^8 row completes the two's complement, both gated by is_signed_a_i.
//
//   Reduction: one CPR 4:2 per bit plane, then four CPR 4:2 merging the column
//   pairs at weights 2^0/2^1, then one CPR 9:2 merging the four nodes at weights
//   2^0/2^2/2^4/2^6 together with the constant row.
//
//   Widths:
//     stage                          width
//     -----------------------------  -----
//     multiplexer output               6
//     per-column CPR 4:2 (EXT = 2)     8
//     L0 << 1 CPR 4:2 (EXT = 2)       11
//     L1 CPR 9:2 (EXT = 2)            19
//     output (sign-extended)          22
//
//   The output pair is sign-consistent - signext(sum_o) + signext(carry_o) is
//   the dot product, not just its low bits - which is what lets pe_array_bpl_a_bfp
//   sign-extend and re-align it. Combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module dp_8_bpl_a_bfp #(
    localparam int LANES       = 8,
    localparam int IN_WIDTH_A  = 8,
    localparam int IN_WIDTH_B  = 5,
    localparam int SUM_WIDTH   = 6,
    localparam int NUM_BLK     = LANES / 2,
    localparam int NUM_COL     = IN_WIDTH_A,
    localparam int MUX_WIDTH   = SUM_WIDTH,
    localparam int MUX_SIZE    = 4,
    localparam int COL_EXT     = 2,
    localparam int COL_WIDTH   = MUX_WIDTH + COL_EXT,
    localparam int NUM_L0      = NUM_COL / 2,
    localparam int SH_L0       = 1,
    localparam int L0_IN_WIDTH = COL_WIDTH + SH_L0,
    localparam int L0_EXT      = 2,
    localparam int L0_WIDTH    = L0_IN_WIDTH + L0_EXT,
    localparam int SH_L1       = 2,
    localparam int L1_IN_WIDTH = L0_WIDTH + SH_L1 * (NUM_L0 - 1),
    localparam int L1_IN_SIZE  = 2 * NUM_L0 + 1,
    localparam int L1_EXT      = 2,
    localparam int L1_WIDTH    = L1_IN_WIDTH + L1_EXT,
    localparam int OUT_EXT     = 3,
    localparam int OUT_WIDTH   = L1_WIDTH + OUT_EXT
)(
    input  logic [IN_WIDTH_A-1:0] a_i     [  0:LANES-1],
    input  logic [IN_WIDTH_B-1:0] b_i     [  0:LANES-1],
    input  logic [ SUM_WIDTH-1:0] b_sum_i [0:NUM_BLK-1],
    input  logic                  is_signed_a_i,
    output logic [ OUT_WIDTH-1:0] sum_o,
    output logic [ OUT_WIDTH-1:0] carry_o
);

    logic [  MUX_WIDTH-1:0] b_w       [     0:LANES-1];
    logic [  MUX_WIDTH-1:0] mux_out   [   0:NUM_BLK-1][0:NUM_COL-1];
    logic [  COL_WIDTH-1:0] col_sum   [   0:NUM_COL-1];
    logic [  COL_WIDTH-1:0] col_carry [   0:NUM_COL-1];
    logic [  COL_WIDTH-1:0] top_in    [           0:1];
    logic [  COL_WIDTH-1:0] top_out   [           0:1];
    logic [  COL_WIDTH-1:0] col_s     [   0:NUM_COL-1];
    logic [  COL_WIDTH-1:0] col_c     [   0:NUM_COL-1];
    logic [   L0_WIDTH-1:0] l0_sum    [    0:NUM_L0-1];
    logic [   L0_WIDTH-1:0] l0_carry  [    0:NUM_L0-1];
    logic [L1_IN_WIDTH-1:0] l1_in     [0:L1_IN_SIZE-1];
    logic [   L1_WIDTH-1:0] l1_pair   [           0:1];
    logic [  OUT_WIDTH-1:0] out_pair  [           0:1];

    genvar j, h, g;

    ext_n #(
        .WIDTH    (IN_WIDTH_B),
        .SIZE     (LANES),
        .EXT      (MUX_WIDTH-IN_WIDTH_B),
        .IS_SIGNED(1'b1)
    ) ext_n_b_i (
        .in_i (b_i),
        .out_o(b_w)
    );

    generate
        for (j = 0; j < NUM_BLK; j++) begin : gen_blk
            for (h = 0; h < NUM_COL; h++) begin : gen_plane
                logic [MUX_WIDTH-1:0] mux_in [0:MUX_SIZE-1];
                logic [          1:0] mux_sel;

                assign mux_in[0] = '0;
                assign mux_in[1] = b_w[2*j+0];
                assign mux_in[2] = b_w[2*j+1];
                assign mux_in[3] = b_sum_i[j];
                assign mux_sel   = {a_i[2*j+1][h], a_i[2*j+0][h]};

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
        for (h = 0; h < NUM_COL; h++) begin : gen_col
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

    assign top_in[0] = col_sum[NUM_COL-1];
    assign top_in[1] = col_carry[NUM_COL-1];

    comp_n #(
        .WIDTH(COL_WIDTH),
        .SIZE (2)
    ) comp_n_i (
        .in_i (top_in),
        .neg_i(is_signed_a_i),
        .out_o(top_out)
    );

    generate
        for (h = 0; h < NUM_COL-1; h++) begin : gen_pass
            assign col_s[h] = col_sum[h];
            assign col_c[h] = col_carry[h];
        end
    endgenerate

    assign col_s[NUM_COL-1] = top_out[0];
    assign col_c[NUM_COL-1] = top_out[1];

    generate
        for (g = 0; g < NUM_L0; g++) begin : gen_l0
            logic [L0_IN_WIDTH-1:0] l0_in [0:3];

            assign l0_in[0] = L0_IN_WIDTH'($signed(col_s[2*g+1])) << SH_L0;
            assign l0_in[1] = L0_IN_WIDTH'($signed(col_c[2*g+1])) << SH_L0;
            assign l0_in[2] = L0_IN_WIDTH'($signed(col_s[2*g+0]));
            assign l0_in[3] = L0_IN_WIDTH'($signed(col_c[2*g+0]));

            cpr_w_n #(
                .IN_WIDTH (L0_IN_WIDTH),
                .IN_SIZE  (4),
                .EXT      (L0_EXT),
                .IS_SIGNED(1'b1)
            ) cpr_w_n_i (
                .in_i   (l0_in),
                .sum_o  (l0_sum[g]),
                .carry_o(l0_carry[g])
            );
        end
    endgenerate

    generate
        for (g = 0; g < NUM_L0; g++) begin : gen_l1_align
            assign l1_in[2*g+0] = L1_IN_WIDTH'($signed(l0_sum[g]))   << (SH_L1*g);
            assign l1_in[2*g+1] = L1_IN_WIDTH'($signed(l0_carry[g])) << (SH_L1*g);
        end
    endgenerate

    assign l1_in[L1_IN_SIZE-1] = is_signed_a_i ? L1_IN_WIDTH'(1 << IN_WIDTH_A) : '0;

    cpr_w_n #(
        .IN_WIDTH (L1_IN_WIDTH),
        .IN_SIZE  (L1_IN_SIZE),
        .EXT      (L1_EXT),
        .IS_SIGNED(1'b1)
    ) cpr_w_n_l1_i (
        .in_i   (l1_in),
        .sum_o  (l1_pair[0]),
        .carry_o(l1_pair[1])
    );

    ext_n #(
        .WIDTH    (L1_WIDTH),
        .SIZE     (2),
        .EXT      (OUT_EXT),
        .IS_SIGNED(1'b1)
    ) ext_n_out_i (
        .in_i (l1_pair),
        .out_o(out_pair)
    );

    assign sum_o   = out_pair[0];
    assign carry_o = out_pair[1];

endmodule
