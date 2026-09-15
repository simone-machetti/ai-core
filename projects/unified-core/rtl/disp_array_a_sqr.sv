// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   A-operand dispatch array for the square variant - the A half of the operand
//   dispatch, shared by a whole grid row (one instance per row drives every PE
//   in that row). Same routing as disp_array_a (one 4->1 block select per pair,
//   broadcast to the pair), but each DP8 output is centered and idle-zeroed by a
//   per-DP8 gate_a_n_sqr instead of passed raw.
//
//   Centering (flip each nibble MSB iff unsigned) is done here so it is shared
//   by the PE and the alpha/beta generators; the square datapath then works on
//   pre-centered nibbles. zero_i[d] forces DP8 d's operand to a real zero (idle
//   DP8, modes 5/6). is_signed_a_i / zero_i are per-DP8 (the two DP8s of a pair
//   can differ), so there are 16 gate_a_n_sqr instances.
//
//   The 256-bit operand is registered on input; the dispatch is combinational
//   and its output is broadcast to the row's PEs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_a_sqr #(
    localparam int NUM_BLK     = 4,
    localparam int BLK_WIDTH   = 64,
    localparam int NUM_PAIR    = 8,
    localparam int NUM_DP8     = 16,
    localparam int SEL_WIDTH   = $clog2(NUM_BLK),
    localparam int A_DP8_WIDTH = BLK_WIDTH,
    localparam int A_ELEM      = 8,
    localparam int NUM_A_ELEM  = BLK_WIDTH / A_ELEM
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_a_i,
    input  logic [        SEL_WIDTH-1:0] sel_a_i       [0:NUM_PAIR-1],
    input  logic                         is_signed_a_i [ 0:NUM_DP8-1],
    input  logic                         zero_i        [ 0:NUM_DP8-1],
    output logic [      A_DP8_WIDTH-1:0] a_dp8_o       [ 0:NUM_DP8-1]
);

    logic [BLK_WIDTH-1:0] a_blk   [0:NUM_BLK-1];
    logic [BLK_WIDTH-1:0] a_blk_q [0:NUM_BLK-1];

    genvar b, p, d;

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
            logic [BLK_WIDTH-1:0] a_sel;
            logic [   A_ELEM-1:0] a_lane [0:NUM_A_ELEM-1];

            mux_n #(
                .WIDTH(BLK_WIDTH),
                .SIZE (NUM_BLK)
            ) mux_n_a_i (
                .in_i (a_blk_q),
                .sel_i(sel_a_i[p]),
                .out_o(a_sel)
            );

            for (genvar e = 0; e < NUM_A_ELEM; e++) begin : gen_split
                assign a_lane[e] = a_sel[e*A_ELEM +: A_ELEM];
            end

            for (d = 0; d < 2; d++) begin : gen_dp8
                logic [A_ELEM-1:0] o_lane [0:NUM_A_ELEM-1];

                gate_a_n_sqr #(
                    .WIDTH(A_ELEM),
                    .SIZE (NUM_A_ELEM)
                ) gate_a_n_sqr_i (
                    .in_i       (a_lane),
                    .is_signed_i(is_signed_a_i[2*p+d]),
                    .zero_i     (zero_i[2*p+d]),
                    .out_o      (o_lane)
                );

                for (genvar e = 0; e < NUM_A_ELEM; e++) begin : gen_pack
                    assign a_dp8_o[2*p+d][e*A_ELEM +: A_ELEM] = o_lane[e];
                end
            end
        end
    endgenerate

endmodule
