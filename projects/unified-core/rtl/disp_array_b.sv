// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   B-operand dispatch array - the B half of the operand dispatch, shared by a
//   whole grid column (one instance per column drives every PE in that column).
//   Routes the 256-bit B operand to the 16 DP8s using one 4->1 block select per
//   pair, a fixed B high/low split, and per-DP8 B gating. Fixed to the PE config.
//
//   Layout:
//     - pe_in_b_i is 4 blocks x 64 bits (block b = [b*64 +: 64]); a B block is two
//       32-bit halves, each 8 x int4. The 16 DP8s form 8 pairs; pair p = (2p,2p+1).
//     - MUX B (4->1, 64b) selects one B block; its high 32 bits (H) go to the even
//       DP8 (2p), its low 32 bits (L) to the odd DP8 (2p+1).
//     - Each B half passes through a gate_b_n (per int4 element): pass / zero
//       (idle lane) / negate (complex-mode imaginary term); ctr_h_i[p] gates the
//       even (H) lane, ctr_l_i[p] the odd (L) lane. Negating an int8 B negates its
//       two int4 nibbles across the two halves, so the low (L) gate does the two's-
//       complement negate and its carry-out is routed into the high (H) gate as
//       the carry-in of a negate-carry (L uses GATE_NEG, H uses GATE_NEG_CARRY).
//
//   The 256-bit operand is registered on input; the dispatch is combinational and
//   its output is broadcast to the column's PEs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_b #(
    localparam int NUM_BLK      = 4,
    localparam int BLK_WIDTH    = 64,
    localparam int NUM_PAIR     = 8,
    localparam int NUM_DP8      = 16,
    localparam int SEL_WIDTH    = $clog2(NUM_BLK),
    localparam int B_DP8_WIDTH  = BLK_WIDTH / 2,
    localparam int B_ELEM_WIDTH = 4,
    localparam int NUM_B_ELEM   = B_DP8_WIDTH / B_ELEM_WIDTH,
    localparam int OP_WIDTH     = 2
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b_i,
    input  logic [        SEL_WIDTH-1:0] sel_b_i [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_l_i [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_h_i [0:NUM_PAIR-1],
    output logic [      B_DP8_WIDTH-1:0] b_dp8_o [ 0:NUM_DP8-1]
);

    logic [BLK_WIDTH-1:0] b_blk   [0:NUM_BLK-1];
    logic [BLK_WIDTH-1:0] b_blk_q [0:NUM_BLK-1];

    genvar b, p, e;

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
                assign bhi_nib[e] = b_sel[B_DP8_WIDTH + e*B_ELEM_WIDTH +: B_ELEM_WIDTH];
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

            for (e = 0; e < NUM_B_ELEM; e++) begin : gen_pack
                assign b_dp8_o[2*p+0][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = bhi_gated[e];
                assign b_dp8_o[2*p+1][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = blo_gated[e];
            end
        end
    endgenerate

endmodule
