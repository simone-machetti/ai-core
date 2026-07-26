// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   BFP two-bundle alignment cell. Takes two bundles of rows, each bundle
//   sharing one unsigned exponent (bias-agnostic), and outputs both bundles at
//   the common scale exp_o = max(exp_0_i, exp_1_i): the rows of the
//   smaller-exponent bundle are right-shifted by |exp_0_i - exp_1_i|
//   (truncating; amounts at or beyond the 2*WIDTH fill window flush to the
//   fill extension), the other bundle passes through bit-identical, and the
//   aligned rows leave as one vector in input order (out_o[0 +: SIZE_0] from
//   in_0_i, out_o[SIZE_0 +: SIZE_1] from in_1_i). On equal exponents
//   bundle 1 nominally traverses the shifter with amount 0, so the cell is
//   fully transparent (the pure-integer path). The shift is arithmetic
//   (sign-fill) when IS_SIGNED, logical otherwise.
//
//   Built structurally from three primitives: sub_n_bfp computes the exponent
//   difference (sign_o drives every select, abs_o is the shift amount), mux_n
//   implements every select (max exponent, per-slot row/fill swap, per-row
//   output un-swap), and one shift_n_bfp shifts all NUM_SH slots inside their
//   {fill, row} windows. Slots whose row exists in only one bundle (unequal
//   SIZE_0/SIZE_1) skip the swap muxes and wire that bundle's row straight to
//   the shifter: their shifted value is observable only when that bundle is
//   the one shifting, so the mux against a constant zero would be redundant.
//
//   Lane-fusion chain (H/L lane pairs, gate_b_n carry idiom): chain_*_o feed
//   the raw input rows through to the L neighbour; with chain_en_i set, the
//   fill of the shifter window comes from chain_*_i (the H neighbour's rows)
//   instead of the sign replication, so the two cells of a pair form one
//   distributed 2*WIDTH shifter. A fused pair must receive equal exponents on
//   both cells. Tie chain_en_i low (and chain_*_i to zero) for standalone use.
//
//   The parent is responsible for presenting the minimum exponent on a
//   zeroed/idle bundle so it never wins the max. Building cell of the
//   tree-structured align_bfp.
//
// Parameters:
//   WIDTH     - row width
//   SIZE_0    - number of rows in bundle 0 (share exp_0_i)
//   SIZE_1    - number of rows in bundle 1 (share exp_1_i)
//   EXP_WIDTH - exponent width (unsigned)
//   IS_SIGNED - 1: arithmetic (sign-fill) right shift, 0: logical
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module align_cell_bfp #(
    parameter  int WIDTH     = 20,
    parameter  int SIZE_0    = 2,
    parameter  int SIZE_1    = 2,
    parameter  int EXP_WIDTH = 8,
    parameter  bit IS_SIGNED = 1'b1,
    localparam int NUM_SH    = (SIZE_0 > SIZE_1) ? SIZE_0 : SIZE_1,
    localparam int MIN_SH    = (SIZE_0 < SIZE_1) ? SIZE_0 : SIZE_1,
    localparam int SIZE_OUT  = SIZE_0 + SIZE_1
)(
    input  logic [    WIDTH-1:0] in_0_i    [  0:SIZE_0-1],
    input  logic [EXP_WIDTH-1:0] exp_0_i,
    input  logic [    WIDTH-1:0] in_1_i    [  0:SIZE_1-1],
    input  logic [EXP_WIDTH-1:0] exp_1_i,
    input  logic                 chain_en_i,
    input  logic [    WIDTH-1:0] chain_0_i [  0:SIZE_0-1],
    input  logic [    WIDTH-1:0] chain_1_i [  0:SIZE_1-1],
    output logic [    WIDTH-1:0] chain_0_o [  0:SIZE_0-1],
    output logic [    WIDTH-1:0] chain_1_o [  0:SIZE_1-1],
    output logic [    WIDTH-1:0] out_o     [0:SIZE_OUT-1],
    output logic [EXP_WIDTH-1:0] exp_o
);

    logic [EXP_WIDTH-1:0] amount;
    logic                 msb;
    logic [EXP_WIDTH-1:0] exp_in [0:1];

    logic [WIDTH-1:0] row_sel  [0:NUM_SH-1];
    logic [WIDTH-1:0] fill_sel [0:NUM_SH-1];
    logic [WIDTH-1:0] sh_out   [0:NUM_SH-1];

    sub_n_bfp #(
        .WIDTH(EXP_WIDTH)
    ) sub_n_bfp_i (
        .in_0_i(exp_0_i),
        .in_1_i(exp_1_i),
        .abs_o (amount),
        .sign_o(msb)
    );

    assign exp_in[0] = exp_0_i;
    assign exp_in[1] = exp_1_i;

    mux_n #(
        .WIDTH(EXP_WIDTH),
        .SIZE (2)
    ) mux_n_exp_i (
        .in_i (exp_in),
        .sel_i(msb),
        .out_o(exp_o)
    );

    genvar s, r;
    generate
        for (s = 0; s < NUM_SH; s++) begin : gen_slot
            logic [WIDTH-1:0] chain_sel;

            if (s < MIN_SH) begin : gen_mux
                logic [WIDTH-1:0] row_in   [0:1];
                logic [WIDTH-1:0] chain_in [0:1];

                assign row_in[0]   = in_1_i[s];
                assign row_in[1]   = in_0_i[s];
                assign chain_in[0] = chain_1_i[s];
                assign chain_in[1] = chain_0_i[s];

                mux_n #(
                    .WIDTH(WIDTH),
                    .SIZE (2)
                ) mux_n_row_i (
                    .in_i (row_in),
                    .sel_i(msb),
                    .out_o(row_sel[s])
                );

                mux_n #(
                    .WIDTH(WIDTH),
                    .SIZE (2)
                ) mux_n_fill_i (
                    .in_i (chain_in),
                    .sel_i(msb),
                    .out_o(chain_sel)
                );
            end else if (SIZE_0 > SIZE_1) begin : gen_wire_0
                assign row_sel[s] = in_0_i[s];
                assign chain_sel  = chain_0_i[s];
            end else begin : gen_wire_1
                assign row_sel[s] = in_1_i[s];
                assign chain_sel  = chain_1_i[s];
            end

            assign fill_sel[s] = chain_en_i ? chain_sel : {WIDTH{IS_SIGNED & row_sel[s][WIDTH-1]}};
        end
    endgenerate

    shift_n_bfp #(
        .WIDTH    (WIDTH),
        .SIZE     (NUM_SH),
        .AMT_WIDTH(EXP_WIDTH),
        .IS_SIGNED(IS_SIGNED)
    ) shift_n_bfp_i (
        .in_i  (row_sel),
        .fill_i(fill_sel),
        .amt_i (amount),
        .out_o (sh_out)
    );

    generate
        for (r = 0; r < SIZE_0; r++) begin : gen_out_0
            logic [WIDTH-1:0] out_in [0:1];

            assign out_in[0] = in_0_i[r];
            assign out_in[1] = sh_out[r];

            mux_n #(
                .WIDTH(WIDTH),
                .SIZE (2)
            ) mux_n_out_i (
                .in_i (out_in),
                .sel_i(msb),
                .out_o(out_o[r])
            );

            assign chain_0_o[r] = in_0_i[r];
        end

        for (r = 0; r < SIZE_1; r++) begin : gen_out_1
            logic [WIDTH-1:0] out_in [0:1];

            assign out_in[0] = sh_out[r];
            assign out_in[1] = in_1_i[r];

            mux_n #(
                .WIDTH(WIDTH),
                .SIZE (2)
            ) mux_n_out_i (
                .in_i (out_in),
                .sel_i(msb),
                .out_o(out_o[SIZE_0+r])
            );

            assign chain_1_o[r] = in_1_i[r];
        end
    endgenerate

endmodule
