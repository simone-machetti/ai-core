// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   B-exponent dispatch array - the BFP exponent sideband counterpart of
//   disp_array_b, shared by a whole grid column (one instance per column,
//   next to the mantissa dispatcher it mirrors). Routes the 4 per-block B
//   exponent chunks (one 12-bit chunk per 64-bit B block: the exponents of
//   its two 32-bit halves, since plane packing can put two halves with
//   different exponents in one block) to the 16 DP8s using the same 4->1
//   block select per pair and the same fixed high/low split as the mantissa
//   path: chunk bits [11:6] are the exponent of the block's high (H) half and
//   go to the even DP8 (2p), bits [5:0] belong to the low (L) half and go to
//   the odd DP8 (2p+1). Each half is then gated to zero when its lane is idle
//   (ctr_h_i / ctr_l_i at the ZERO code only), so an idle DP8 presents the
//   minimum scale to the PE array and never wins an alignment max. The NEG /
//   NEG_CARRY codes pass the exponent through unchanged: negating a mantissa
//   does not change its scale (never a gate_b_n here - it would negate the
//   exponents in the complex modes).
//
//   The 48-bit exponent word is registered on input, in step with the 256-bit
//   operand register of disp_array_b; the dispatch is combinational and its
//   output is broadcast to the column's PEs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_exp_b_bfp #(
    localparam int NUM_BLK   = 4,
    localparam int EXP_WIDTH = 6,
    localparam int CHK_WIDTH = 2 * EXP_WIDTH,
    localparam int NUM_PAIR  = 8,
    localparam int NUM_DP8   = 16,
    localparam int SEL_WIDTH = $clog2(NUM_BLK),
    localparam int OP_WIDTH  = 2
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*CHK_WIDTH-1:0] pe_exp_b_i,
    input  logic [        SEL_WIDTH-1:0] sel_b_i     [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_l_i     [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_h_i     [0:NUM_PAIR-1],
    output logic [        EXP_WIDTH-1:0] exp_b_dp8_o [ 0:NUM_DP8-1]
);

    localparam logic [OP_WIDTH-1:0] GATE_ZERO = 2'b01;

    logic [CHK_WIDTH-1:0] exp_blk   [0:NUM_BLK-1];
    logic [CHK_WIDTH-1:0] exp_blk_q [0:NUM_BLK-1];

    genvar b, p;

    generate
        for (b = 0; b < NUM_BLK; b++) begin : gen_reshape
            assign exp_blk[b] = pe_exp_b_i[b*CHK_WIDTH +: CHK_WIDTH];
        end
    endgenerate

    reg_n #(
        .WIDTH(CHK_WIDTH),
        .SIZE (NUM_BLK)
    ) reg_n_exp_b_i (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .d_i   (exp_blk),
        .q_o   (exp_blk_q)
    );

    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_pair
            logic [CHK_WIDTH-1:0] exp_sel;
            logic [EXP_WIDTH-1:0] exp_split [0:1];
            logic [EXP_WIDTH-1:0] exp_h     [0:0];
            logic [EXP_WIDTH-1:0] exp_l     [0:0];

            mux_n #(
                .WIDTH(CHK_WIDTH),
                .SIZE (NUM_BLK)
            ) mux_n_exp_i (
                .in_i (exp_blk_q),
                .sel_i(sel_b_i[p]),
                .out_o(exp_sel)
            );

            assign exp_split[0] = exp_sel[CHK_WIDTH-1:EXP_WIDTH];
            assign exp_split[1] = exp_sel[EXP_WIDTH-1:0];

            gate_n #(
                .WIDTH(EXP_WIDTH),
                .SIZE (1)
            ) gate_n_h_i (
                .in_i (exp_split[0:0]),
                .sel_i(ctr_h_i[p] == GATE_ZERO),
                .out_o(exp_h)
            );

            gate_n #(
                .WIDTH(EXP_WIDTH),
                .SIZE (1)
            ) gate_n_l_i (
                .in_i (exp_split[1:1]),
                .sel_i(ctr_l_i[p] == GATE_ZERO),
                .out_o(exp_l)
            );

            assign exp_b_dp8_o[2*p+0] = exp_h[0];
            assign exp_b_dp8_o[2*p+1] = exp_l[0];
        end
    endgenerate

endmodule
