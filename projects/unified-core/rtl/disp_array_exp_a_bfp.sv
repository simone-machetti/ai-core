// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   A-exponent dispatch array - the BFP exponent sideband counterpart of
//   disp_array_a, shared by a whole grid row (one instance per row, next to
//   the mantissa dispatcher it mirrors). Routes the 4 per-block A format
//   exponents (one 6-bit exponent per 64-bit A block, the source rule) to the
//   16 DP8s using the same 4->1 block select per pair, then gates each half
//   of the pair to zero when its B lane is idle (ctr_h_i for the even DP8,
//   ctr_l_i for the odd one, ZERO code only). The mantissa dispatcher needs
//   no gate on A - a zeroed B mantissa already kills the product - but
//   exponents add in the PE array (scale = e_A + e_B), so an idle DP8 must
//   have BOTH exponent sides zeroed or its leftover scale could win an
//   alignment max and wrongly right-shift active data. The NEG / NEG_CARRY
//   codes pass the exponent through unchanged: negating a mantissa does not
//   change its scale (never a gate_b_n here - it would negate the exponents
//   in the complex modes).
//
//   The 24-bit exponent word is registered on input, in step with the 256-bit
//   operand register of disp_array_a; the dispatch is combinational and its
//   output is broadcast to the row's PEs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_exp_a_bfp #(
    localparam int NUM_BLK   = 4,
    localparam int EXP_WIDTH = 6,
    localparam int NUM_PAIR  = 8,
    localparam int NUM_DP8   = 16,
    localparam int SEL_WIDTH = $clog2(NUM_BLK),
    localparam int OP_WIDTH  = 2
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*EXP_WIDTH-1:0] pe_exp_a_i,
    input  logic [        SEL_WIDTH-1:0] sel_a_i     [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_l_i     [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_h_i     [0:NUM_PAIR-1],
    output logic [        EXP_WIDTH-1:0] exp_a_dp8_o [ 0:NUM_DP8-1]
);

    localparam logic [OP_WIDTH-1:0] GATE_ZERO = 2'b01;

    logic [EXP_WIDTH-1:0] exp_blk   [0:NUM_BLK-1];
    logic [EXP_WIDTH-1:0] exp_blk_q [0:NUM_BLK-1];

    genvar b, p;

    generate
        for (b = 0; b < NUM_BLK; b++) begin : gen_reshape
            assign exp_blk[b] = pe_exp_a_i[b*EXP_WIDTH +: EXP_WIDTH];
        end
    endgenerate

    reg_n #(
        .WIDTH(EXP_WIDTH),
        .SIZE (NUM_BLK)
    ) reg_n_exp_a_i (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .d_i   (exp_blk),
        .q_o   (exp_blk_q)
    );

    generate
        for (p = 0; p < NUM_PAIR; p++) begin : gen_pair
            logic [EXP_WIDTH-1:0] exp_sel;
            logic [EXP_WIDTH-1:0] exp_pair [0:1];
            logic [EXP_WIDTH-1:0] exp_h    [0:0];
            logic [EXP_WIDTH-1:0] exp_l    [0:0];

            mux_n #(
                .WIDTH(EXP_WIDTH),
                .SIZE (NUM_BLK)
            ) mux_n_exp_i (
                .in_i (exp_blk_q),
                .sel_i(sel_a_i[p]),
                .out_o(exp_sel)
            );

            assign exp_pair[0] = exp_sel;
            assign exp_pair[1] = exp_sel;

            gate_n #(
                .WIDTH(EXP_WIDTH),
                .SIZE (1)
            ) gate_n_h_i (
                .in_i (exp_pair[0:0]),
                .sel_i(ctr_h_i[p] == GATE_ZERO),
                .out_o(exp_h)
            );

            gate_n #(
                .WIDTH(EXP_WIDTH),
                .SIZE (1)
            ) gate_n_l_i (
                .in_i (exp_pair[1:1]),
                .sel_i(ctr_l_i[p] == GATE_ZERO),
                .out_o(exp_l)
            );

            assign exp_a_dp8_o[2*p+0] = exp_h[0];
            assign exp_a_dp8_o[2*p+1] = exp_l[0];
        end
    endgenerate

endmodule
