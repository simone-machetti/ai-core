// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   B-operand dispatch array, bit-plane build - the disp_array_b variant that
//   also produces the operands dp_8_bpl_bfp needs. Routing is unchanged from
//   disp_array_b: one 4->1 block select per pair, a fixed B high/low split and
//   per-DP8 B gating, all shared by a whole grid column.
//
//   What is added is one gate_b_n_bpl_bfp per DP8, downstream of the gate, which
//   turns each half's eight conditioned int4 nibbles into
//     - b_dp8_o     : the same eight values widened to 5 bits, each already the
//                     exact signed number its DP8 must multiply
//     - b_sum_dp8_o : the four pairwise sums (nibble 2k plus 2k+1) at 6 bits
//   It sits after the gate, not before, because the sums must be of the values
//   the DP8 actually sees - zeroed for an idle lane, negated for a complex-mode
//   imaginary term (the negate carry crosses the H/L halves, never a lane pair,
//   so pairing stays inside one DP8).
//
//   Both outputs are broadcast to the column's PEs, so the pairwise adders are
//   paid once per column instead of once per PE - the amortization the bit-plane
//   variant exists for. Because the values leave here already resolved, the
//   per-DP8 signedness is consumed here (is_signed_b_i, straight from ctrl) and
//   never reaches the PEs.
//
//   The 256-bit operand is registered on input; the dispatch is combinational.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_b_bpl_bfp #(
    localparam int NUM_BLK       = 4,
    localparam int BLK_WIDTH     = 64,
    localparam int NUM_PAIR      = 8,
    localparam int NUM_DP8       = 16,
    localparam int SEL_WIDTH     = $clog2(NUM_BLK),
    localparam int B_HALF_WIDTH  = BLK_WIDTH / 2,
    localparam int B_ELEM_WIDTH  = 4,
    localparam int NUM_B_ELEM    = B_HALF_WIDTH / B_ELEM_WIDTH,
    localparam int OP_WIDTH      = 2,
    localparam int B_OUT_WIDTH   = B_ELEM_WIDTH + 1,
    localparam int B_SUM_WIDTH   = B_ELEM_WIDTH + 2,
    localparam int NUM_B_SUM     = NUM_B_ELEM / 2,
    localparam int B_DP8_WIDTH   = NUM_B_ELEM * B_OUT_WIDTH,
    localparam int B_SDP8_WIDTH  = NUM_B_SUM * B_SUM_WIDTH
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b_i,
    input  logic [        SEL_WIDTH-1:0] sel_b_i       [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_l_i       [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_h_i       [0:NUM_PAIR-1],
    input  logic                         is_signed_b_i [ 0:NUM_DP8-1],
    output logic [      B_DP8_WIDTH-1:0] b_dp8_o       [ 0:NUM_DP8-1],
    output logic [     B_SDP8_WIDTH-1:0] b_sum_dp8_o   [ 0:NUM_DP8-1]
);

    logic [BLK_WIDTH-1:0] b_blk   [0:NUM_BLK-1];
    logic [BLK_WIDTH-1:0] b_blk_q [0:NUM_BLK-1];

    genvar b, p, e, s;

    generate
        for (b = 0; b < NUM_BLK; b++) begin : gen_reshape
            assign b_blk[b] = pe_in_b_i[b*BLK_WIDTH +: BLK_WIDTH];
        end
    endgenerate

    reg_n #(
        .WIDTH(BLK_WIDTH),
        .SIZE (NUM_BLK)
    ) reg_n_b_i (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .d_i   (b_blk),
        .q_o   (b_blk_q)
    );

    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_pair
            logic [   BLK_WIDTH-1:0] b_sel;
            logic [B_ELEM_WIDTH-1:0] blo_nib   [0:NUM_B_ELEM-1];
            logic [B_ELEM_WIDTH-1:0] bhi_nib   [0:NUM_B_ELEM-1];
            logic [B_ELEM_WIDTH-1:0] blo_gated [0:NUM_B_ELEM-1];
            logic [B_ELEM_WIDTH-1:0] bhi_gated [0:NUM_B_ELEM-1];
            logic                    blo_cin   [0:NUM_B_ELEM-1];
            logic                    blo_carry [0:NUM_B_ELEM-1];
            logic [ B_OUT_WIDTH-1:0] blo_ext   [0:NUM_B_ELEM-1];
            logic [ B_OUT_WIDTH-1:0] bhi_ext   [0:NUM_B_ELEM-1];
            logic [ B_SUM_WIDTH-1:0] blo_sum   [ 0:NUM_B_SUM-1];
            logic [ B_SUM_WIDTH-1:0] bhi_sum   [ 0:NUM_B_SUM-1];

            mux_n #(
                .WIDTH(BLK_WIDTH),
                .SIZE (NUM_BLK)
            ) mux_n_b_i (
                .in_i (b_blk_q),
                .sel_i(sel_b_i[p]),
                .out_o(b_sel)
            );

            for (e = 0; e < NUM_B_ELEM; e++) begin : gen_split
                assign blo_nib[e] = b_sel[e*B_ELEM_WIDTH +: B_ELEM_WIDTH];
                assign bhi_nib[e] = b_sel[B_HALF_WIDTH + e*B_ELEM_WIDTH +: B_ELEM_WIDTH];
                assign blo_cin[e] = 1'b0;
            end

            gate_b_n #(
                .WIDTH(B_ELEM_WIDTH),
                .SIZE (NUM_B_ELEM)
            ) gate_b_n_l_i (
                .in_i   (blo_nib),
                .carry_i(blo_cin),
                .sel_i  (ctr_l_i[p]),
                .out_o  (blo_gated),
                .carry_o(blo_carry)
            );

            /* verilator lint_off PINCONNECTEMPTY */
            gate_b_n #(
                .WIDTH(B_ELEM_WIDTH),
                .SIZE (NUM_B_ELEM)
            ) gate_b_n_h_i (
                .in_i   (bhi_nib),
                .carry_i(blo_carry),
                .sel_i  (ctr_h_i[p]),
                .out_o  (bhi_gated),
                .carry_o()
            );
            /* verilator lint_on PINCONNECTEMPTY */

            gate_b_n_bpl_bfp #(
                .WIDTH(B_ELEM_WIDTH),
                .SIZE (NUM_B_ELEM)
            ) gate_b_n_bpl_bfp_h_i (
                .in_i       (bhi_gated),
                .is_signed_i(is_signed_b_i[2*p+0]),
                .out_o      (bhi_ext),
                .sum_o      (bhi_sum)
            );

            gate_b_n_bpl_bfp #(
                .WIDTH(B_ELEM_WIDTH),
                .SIZE (NUM_B_ELEM)
            ) gate_b_n_bpl_bfp_l_i (
                .in_i       (blo_gated),
                .is_signed_i(is_signed_b_i[2*p+1]),
                .out_o      (blo_ext),
                .sum_o      (blo_sum)
            );

            for (e = 0; e < NUM_B_ELEM; e++) begin : gen_pack
                assign b_dp8_o[2*p+0][e*B_OUT_WIDTH +: B_OUT_WIDTH] = bhi_ext[e];
                assign b_dp8_o[2*p+1][e*B_OUT_WIDTH +: B_OUT_WIDTH] = blo_ext[e];
            end

            for (s = 0; s < NUM_B_SUM; s++) begin : gen_pack_sum
                assign b_sum_dp8_o[2*p+0][s*B_SUM_WIDTH +: B_SUM_WIDTH] = bhi_sum[s];
                assign b_sum_dp8_o[2*p+1][s*B_SUM_WIDTH +: B_SUM_WIDTH] = blo_sum[s];
            end
        end
    endgenerate

endmodule
