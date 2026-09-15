// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   B-operand dispatch array for the square variant - the B half of the operand
//   dispatch, shared by a whole grid column (one instance per column drives
//   every PE in that column). Same routing as disp_array_b (one 4->1 block
//   select per pair, high/low int4 split), but each half is centered and
//   idle-zeroed by a per-DP8 gate_b_n_sqr instead of pass/zero/negated.
//
//   Layout:
//     - pe_in_b_i is 4 blocks x 64 bits; a B block is two 32-bit halves, each
//       8 x int4. The 16 DP8s form 8 pairs; pair p = (2p, 2p+1). MUX B selects a
//       block; its high 32 bits (H) go to the even DP8 (2p), its low 32 bits (L)
//       to the odd DP8 (2p+1).
//     - Each half passes through a gate_b_n_sqr: centers each nibble (flip MSB
//       iff unsigned, shared with the PE and beta generator) and, when zero_i is
//       set, forces the DP8's operand to a real zero (idle DP8, modes 5/6).
//
//   The complex-mode B-negate (gate_b_n's GATE_NEG/GATE_NEG_CARRY and its L->H
//   carry chain) is gone - the negation moved into pe_array_sqr. is_signed_b_i
//   and zero_i are per-DP8.
//
//   The 256-bit operand is registered on input; the dispatch is combinational
//   and its output is broadcast to the column's PEs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_b_sqr #(
    localparam int NUM_BLK      = 4,
    localparam int BLK_WIDTH    = 64,
    localparam int NUM_PAIR     = 8,
    localparam int NUM_DP8      = 16,
    localparam int SEL_WIDTH    = $clog2(NUM_BLK),
    localparam int B_DP8_WIDTH  = BLK_WIDTH / 2,
    localparam int B_ELEM_WIDTH = 4,
    localparam int NUM_B_ELEM   = B_DP8_WIDTH / B_ELEM_WIDTH
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b_i,
    input  logic [        SEL_WIDTH-1:0] sel_b_i       [0:NUM_PAIR-1],
    input  logic                         is_signed_b_i [ 0:NUM_DP8-1],
    input  logic                         zero_i        [ 0:NUM_DP8-1],
    output logic [      B_DP8_WIDTH-1:0] b_dp8_o       [ 0:NUM_DP8-1]
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
            end

            gate_b_n_sqr #(
                .WIDTH(B_ELEM_WIDTH),
                .SIZE (NUM_B_ELEM)
            ) gate_b_n_sqr_h_i (
                .in_i       (bhi_nib),
                .is_signed_i(is_signed_b_i[2*p+0]),
                .zero_i     (zero_i[2*p+0]),
                .out_o      (bhi_gated)
            );

            gate_b_n_sqr #(
                .WIDTH(B_ELEM_WIDTH),
                .SIZE (NUM_B_ELEM)
            ) gate_b_n_sqr_l_i (
                .in_i       (blo_nib),
                .is_signed_i(is_signed_b_i[2*p+1]),
                .zero_i     (zero_i[2*p+1]),
                .out_o      (blo_gated)
            );

            for (e = 0; e < NUM_B_ELEM; e++) begin : gen_pack
                assign b_dp8_o[2*p+0][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = bhi_gated[e];
                assign b_dp8_o[2*p+1][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = blo_gated[e];
            end
        end
    endgenerate

endmodule
