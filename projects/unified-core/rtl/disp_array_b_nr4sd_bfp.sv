// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   B-operand dispatch array for the NR4SD variant - disp_array_b with the hybrid
//   NR4SD+/Booth recoders folded in, shared by a whole grid column (one instance
//   per column drives every PE in that column).
//
//   Routing, splitting and gating are identical to disp_array_b:
//     - pe_in_b_i is 4 blocks x 64 bits (block b = [b*64 +: 64]); a B block is two
//       32-bit halves, each 8 x int4. The 16 DP8s form 8 pairs; pair p = (2p,2p+1).
//     - MUX B (4->1, 64b) selects one B block; its high 32 bits (H) go to the even
//       DP8 (2p), its low 32 bits (L) to the odd DP8 (2p+1).
//     - Each B half passes through a gate_b_n (per int4 element): pass / zero /
//       negate; ctr_h_i[p] gates the even (H) lane, ctr_l_i[p] the odd (L) lane,
//       with the L gate's carry-out routed into the H gate as the negate carry-in.
//
//   What is new is the stage AFTER the gates: one nr4sd_r4 per int4 element per
//   DP8 (16 x 8 = 128 recoders) turns each gated nibble into TWO digit codes - a
//   2-bit NR4SD+ code (weight 1) and a 3-bit Booth window (weight 4) - so the
//   column broadcasts b_nr4sd_dp8_o / b_booth_dp8_o instead of raw B. The recoders
//   must sit after the gating because they recode the value the DP8 actually
//   multiplies, negate and idle-zero included.
//
//   Every nibble is read as SIGNED (see nr4sd_r4), so a nibble that is a lower
//   slice of a wider element comes out 16*b3 too small, and the nibble above
//   repays it through its carry-in. That link is one AND per lane:
//
//     c_in[i][e] = ~is_signed_b_i[i+1] & gated_nibble[i+1][e][3]
//
//   is_signed_b_i[i] therefore means "DP8 i holds the top nibble of its element":
//   the DP8 above an unsigned (lower) nibble takes that nibble's MSB, the DP8
//   above a signed (top) nibble takes 0. The mapping below-in-significance = next
//   DP8 index holds in every mode: within a pair the L nibble (2p+1) sits under
//   the H nibble (2p); for 16-bit B the quad 4q..4q+3 carries hh, hl, lh, ll with
//   the high byte in the even pair, so 4q+1 (hl) links to 4q+2 (lh) across the
//   pair boundary. 4q+3 is always the bottom of its element, so those four DP8s
//   (and DP8 15) have no link: 12 AND groups, not 16. An idle DP8 is a zero
//   nibble, so a link from it is harmless. ctrl is unchanged: it still emits
//   is_signed_b per DP8, only its consumer has moved.
//
//   Bus cost: 8 x (2 + 3) = 40 bits per DP8 against raw B's 32, i.e. +25% (the
//   3-digit NR4SD+ build needed 48, +50%; hoisting Booth needs 72, +125%).
//
//   The 256-bit operand is registered on input; routing, gating, linking and
//   recoding are combinational and the result is broadcast to the column's PEs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_b_nr4sd_bfp #(
    localparam int NUM_BLK           = 4,
    localparam int BLK_WIDTH         = 64,
    localparam int NUM_PAIR          = 8,
    localparam int NUM_DP8           = 16,
    localparam int SEL_WIDTH         = $clog2(NUM_BLK),
    localparam int B_DP8_WIDTH       = BLK_WIDTH / 2,
    localparam int B_ELEM_WIDTH      = 4,
    localparam int NUM_B_ELEM        = B_DP8_WIDTH / B_ELEM_WIDTH,
    localparam int OP_WIDTH          = 2,
    localparam int CODE_WIDTH        = 2,
    localparam int BOOTH_SEL_WIDTH   = 3,
    localparam int B_NR4SD_DP8_WIDTH = NUM_B_ELEM * CODE_WIDTH,
    localparam int B_BOOTH_DP8_WIDTH = NUM_B_ELEM * BOOTH_SEL_WIDTH
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b_i,
    input  logic [        SEL_WIDTH-1:0] sel_b_i       [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_l_i       [0:NUM_PAIR-1],
    input  logic [         OP_WIDTH-1:0] ctr_h_i       [0:NUM_PAIR-1],
    input  logic                         is_signed_b_i [ 0:NUM_DP8-1],
    output logic [B_NR4SD_DP8_WIDTH-1:0] b_nr4sd_dp8_o [ 0:NUM_DP8-1],
    output logic [B_BOOTH_DP8_WIDTH-1:0] b_booth_dp8_o [ 0:NUM_DP8-1]
);

    logic [   BLK_WIDTH-1:0] b_blk     [0:NUM_BLK-1];
    logic [   BLK_WIDTH-1:0] b_blk_q   [0:NUM_BLK-1];
    logic [B_ELEM_WIDTH-1:0] nib_gated [0:NUM_DP8-1][0:NUM_B_ELEM-1];
    logic                    c_in      [0:NUM_DP8-1][0:NUM_B_ELEM-1];

    genvar b, p, e, i;

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

            for (e = 0; e < NUM_B_ELEM; e++) begin : gen_gather
                assign nib_gated[2*p+0][e] = bhi_gated[e];
                assign nib_gated[2*p+1][e] = blo_gated[e];
            end
        end
    endgenerate

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_link
            if (i % 4 == 3) begin : gen_bottom
                for (e = 0; e < NUM_B_ELEM; e++) begin : gen_zero
                    assign c_in[i][e] = 1'b0;
                end
            end else begin : gen_up
                logic link_en;
                assign link_en = ~is_signed_b_i[i+1];
                for (e = 0; e < NUM_B_ELEM; e++) begin : gen_and
                    assign c_in[i][e] = link_en & nib_gated[i+1][e][B_ELEM_WIDTH-1];
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_enc
            for (e = 0; e < NUM_B_ELEM; e++) begin : gen_elem
                nr4sd_r4 #(
                    .IN_WIDTH_B(B_ELEM_WIDTH)
                ) nr4sd_r4_i (
                    .b_i      (nib_gated[i][e]),
                    .c_in_i   (c_in[i][e]),
                    .b_nr4sd_o(b_nr4sd_dp8_o[i][e*CODE_WIDTH +: CODE_WIDTH]),
                    .b_booth_o(b_booth_dp8_o[i][e*BOOTH_SEL_WIDTH +: BOOTH_SEL_WIDTH])
                );
            end
        end
    endgenerate

endmodule
