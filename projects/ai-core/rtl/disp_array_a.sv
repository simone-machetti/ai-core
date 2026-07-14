// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   A-operand dispatch array - the A half of the operand dispatch, shared by a
//   whole grid row (one instance per row drives every PE in that row). Routes the
//   256-bit A operand to the 16 DP8s using one 4->1 block select per pair (no
//   crossbar). Fixed to the PE configuration.
//
//   Layout:
//     - pe_in_a_i is 4 blocks x 64 bits (block b = [b*64 +: 64]); an A block is
//       8 x int8. The 16 DP8s form 8 pairs; pair p = DP8 (2p, 2p+1).
//     - MUX A (4->1, 64b) selects one A block; it feeds BOTH DP8s of the pair
//       (a_dp8_o[2p] = a_dp8_o[2p+1]).
//
//   The 256-bit operand is registered on input; the dispatch is combinational
//   and its output is broadcast to the row's PEs. Operand signedness is decoded
//   by ctrl and sent straight to the DP8s, not routed here.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module disp_array_a #(
    localparam int NUM_BLK     = 4,
    localparam int BLK_WIDTH   = 64,
    localparam int NUM_PAIR    = 8,
    localparam int NUM_DP8     = 16,
    localparam int SEL_WIDTH   = $clog2(NUM_BLK),
    localparam int A_DP8_WIDTH = BLK_WIDTH
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_a_i,
    input  logic [        SEL_WIDTH-1:0] sel_a_i [0:NUM_PAIR-1],
    output logic [      A_DP8_WIDTH-1:0] a_dp8_o [ 0:NUM_DP8-1]
);

    logic [BLK_WIDTH-1:0] a_blk   [0:NUM_BLK-1];
    logic [BLK_WIDTH-1:0] a_blk_q [0:NUM_BLK-1];

    genvar b, p;

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

            mux_n #(
                .WIDTH(BLK_WIDTH),
                .SIZE (NUM_BLK)
            ) mux_n_a_i (
                .in_i (a_blk_q),
                .sel_i(sel_a_i[p]),
                .out_o(a_sel)
            );

            assign a_dp8_o[2*p+0] = a_sel;
            assign a_dp8_o[2*p+1] = a_sel;
        end
    endgenerate

endmodule
