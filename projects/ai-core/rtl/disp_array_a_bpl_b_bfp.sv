// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   A-operand dispatch array, bit-plane B build - the disp_array_a variant that
//   also produces the operands dp_8_bpl_b_bfp needs. Routing is unchanged from
//   disp_array_a: one 4->1 block select per pair, the selected block feeding both
//   DP8s of the pair, all shared by a whole grid row.
//
//   What is added is one gate_n_bpl_bfp per pair, which turns the selected
//   block's eight int8 lanes into
//     - a_dp8_o     : the same eight values widened to 9 bits, each already the
//                     exact signed number its DP8 must multiply
//     - a_sum_dp8_o : the four pairwise sums (lane 2k plus 2k+1) at 10 bits
//
//   One gate per pair, not per DP8: both DP8s of a pair receive the same A block,
//   and ctrl's is_signed_a is uniform within a pair in every mode, so the two
//   DP8s resolve to identical values and identical sums. The gate is therefore
//   driven by is_signed_a_i[2p] and its outputs are broadcast to both entries.
//   A carries no conditioning gate - a lane is idled by zeroing its B - so the
//   gate sits directly after the block select.
//
//   Both outputs are broadcast to the row's PEs, so the pairwise adders are paid
//   once per row instead of once per PE - the amortization the bit-plane variant
//   exists for. Because the values leave here already resolved, the per-DP8
//   signedness is consumed here (is_signed_a_i, straight from ctrl) and never
//   reaches the PEs.
//
//   The 256-bit operand is registered on input; the dispatch is combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_a_bpl_b_bfp #(
    localparam int NUM_BLK      = 4,
    localparam int BLK_WIDTH    = 64,
    localparam int NUM_PAIR     = 8,
    localparam int NUM_DP8      = 16,
    localparam int SEL_WIDTH    = $clog2(NUM_BLK),
    localparam int A_ELEM_WIDTH = 8,
    localparam int NUM_A_ELEM   = BLK_WIDTH / A_ELEM_WIDTH,
    localparam int A_OUT_WIDTH  = A_ELEM_WIDTH + 1,
    localparam int A_SUM_WIDTH  = A_ELEM_WIDTH + 2,
    localparam int NUM_A_SUM    = NUM_A_ELEM / 2,
    localparam int A_DP8_WIDTH  = NUM_A_ELEM * A_OUT_WIDTH,
    localparam int A_SDP8_WIDTH = NUM_A_SUM * A_SUM_WIDTH
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_a_i,
    input  logic [        SEL_WIDTH-1:0] sel_a_i       [0:NUM_PAIR-1],
    input  logic                         is_signed_a_i [ 0:NUM_DP8-1],
    output logic [      A_DP8_WIDTH-1:0] a_dp8_o       [ 0:NUM_DP8-1],
    output logic [     A_SDP8_WIDTH-1:0] a_sum_dp8_o   [ 0:NUM_DP8-1]
);

    logic [BLK_WIDTH-1:0] a_blk   [0:NUM_BLK-1];
    logic [BLK_WIDTH-1:0] a_blk_q [0:NUM_BLK-1];

    genvar b, p, e, s;

    generate
        for (b = 0; b < NUM_BLK; b++) begin : gen_reshape
            assign a_blk[b] = pe_in_a_i[b*BLK_WIDTH +: BLK_WIDTH];
        end
    endgenerate

    reg_n #(
        .WIDTH(BLK_WIDTH),
        .SIZE (NUM_BLK)
    ) reg_n_a_i (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .d_i   (a_blk),
        .q_o   (a_blk_q)
    );

    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_pair
            logic [   BLK_WIDTH-1:0] a_sel;
            logic [A_ELEM_WIDTH-1:0] a_elem [ 0:NUM_A_ELEM-1];
            logic [ A_OUT_WIDTH-1:0] a_res  [ 0:NUM_A_ELEM-1];
            logic [ A_SUM_WIDTH-1:0] a_sum  [  0:NUM_A_SUM-1];

            mux_n #(
                .WIDTH(BLK_WIDTH),
                .SIZE (NUM_BLK)
            ) mux_n_a_i (
                .in_i (a_blk_q),
                .sel_i(sel_a_i[p]),
                .out_o(a_sel)
            );

            for (e = 0; e < NUM_A_ELEM; e++) begin : gen_elem
                assign a_elem[e] = a_sel[e*A_ELEM_WIDTH +: A_ELEM_WIDTH];
            end

            gate_n_bpl_bfp #(
                .WIDTH(A_ELEM_WIDTH),
                .SIZE (NUM_A_ELEM)
            ) gate_n_bpl_bfp_i (
                .in_i       (a_elem),
                .is_signed_i(is_signed_a_i[2*p]),
                .out_o      (a_res),
                .sum_o      (a_sum)
            );

            for (e = 0; e < NUM_A_ELEM; e++) begin : gen_pack
                assign a_dp8_o[2*p+0][e*A_OUT_WIDTH +: A_OUT_WIDTH] = a_res[e];
                assign a_dp8_o[2*p+1][e*A_OUT_WIDTH +: A_OUT_WIDTH] = a_res[e];
            end

            for (s = 0; s < NUM_A_SUM; s++) begin : gen_pack_sum
                assign a_sum_dp8_o[2*p+0][s*A_SUM_WIDTH +: A_SUM_WIDTH] = a_sum[s];
                assign a_sum_dp8_o[2*p+1][s*A_SUM_WIDTH +: A_SUM_WIDTH] = a_sum[s];
            end
        end
    endgenerate

endmodule
