// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized bit-plane operand gate. Takes SIZE input words, WIDTH bits
//   wide, sharing one runtime signedness flag, and produces the two operand
//   sets a bit-plane dot product needs:
//     - out_o : each word widened to WIDTH+1 as its exact signed value - sign-
//               extended when is_signed_i, zero-extended otherwise. One extra
//               bit is enough because an unsigned WIDTH-bit value is always
//               representable in WIDTH+1 bits of two's complement.
//     - sum_o : the SIZE/2 pairwise sums (word 2k plus word 2k+1) at WIDTH+2
//               bits signed. Two bits of growth are required, not one: the
//               unsigned pair reaches 2*(2^WIDTH - 1) - 30 for WIDTH = 4 -
//               which does not fit WIDTH+1 bits of two's complement, while the
//               signed pair reaches -2^WIDTH. WIDTH+2 covers both.
//
//   The pairwise sums are a function of the tabulated operand alone, so this
//   gate lives in the shared dispatch - the per-column B dispatch of the
//   bit-plane A build (disp_array_b_bpl_a_bfp) and the per-row A dispatch of
//   the bit-plane B build (disp_array_a_bpl_b_bfp) - and its cost is amortized
//   over every PE in that column or row, while the bit-plane multiplexers it
//   feeds stay inside each PE. Emitting both operand sets already resolved to
//   signed values is what lets the DP8 core drop the signedness port for that
//   operand entirely. Combinational.
//
// Parameters:
//   WIDTH - bit width of each input word
//   SIZE  - number of input words (even; all share is_signed_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module gate_n_bpl_bfp #(
    parameter int WIDTH = 4,
    parameter int SIZE  = 8,

    localparam int OUT_WIDTH = WIDTH + 1,
    localparam int SUM_WIDTH = WIDTH + 2,
    localparam int NUM_SUM   = SIZE / 2
)(
    input  logic [    WIDTH-1:0] in_i        [   0:SIZE-1],
    input  logic                 is_signed_i,
    output logic [OUT_WIDTH-1:0] out_o       [   0:SIZE-1],
    output logic [SUM_WIDTH-1:0] sum_o       [0:NUM_SUM-1]
);

    logic [OUT_WIDTH-1:0] ext     [   0:SIZE-1];
    logic [SUM_WIDTH-1:0] ext_w   [   0:SIZE-1];
    logic [OUT_WIDTH-1:0] add_sum [0:NUM_SUM-1];
    logic [          0:0] add_cin [0:NUM_SUM-1];
    logic [          0:0] add_cout[0:NUM_SUM-1];

    genvar i, k;

    generate
        for (i = 0; i < SIZE; i++) begin : gen_ext
            assign ext[i]   = {is_signed_i & in_i[i][WIDTH-1], in_i[i]};
            assign out_o[i] = ext[i];
        end
    endgenerate

    ext_n #(
        .WIDTH    (OUT_WIDTH),
        .SIZE     (SIZE),
        .EXT      (1),
        .IS_SIGNED(1'b1)
    ) ext_n_i (
        .in_i (ext),
        .out_o(ext_w)
    );

    generate
        for (k = 0; k < NUM_SUM; k++) begin : gen_pair
            assign add_cin[k] = 1'b0;

            add_n #(
                .WIDTH(OUT_WIDTH),
                .CARRY(1)
            ) add_n_i (
                .in_0_i(ext_w[2*k+0]),
                .in_1_i(ext_w[2*k+1]),
                .cin_i (add_cin[k]),
                .out_o (add_sum[k]),
                .cout_o(add_cout[k])
            );

            assign sum_o[k] = {add_cout[k], add_sum[k]};
        end
    endgenerate

endmodule
