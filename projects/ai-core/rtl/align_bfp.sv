// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   BFP tree aligner for a variable number of exponents. Takes NUM_EXP
//   bundles, each SIZE rows sharing one unsigned exponent (bias-agnostic),
//   and outputs every bundle at the common scale exp_o = max of all input
//   exponents: each row is right-shifted by (exp_o - its bundle exponent),
//   truncating. All aligned rows leave as one flat vector in input order
//   (out_o[k*SIZE+j] aligns with in_i[k][j]).
//   With all exponents equal the module is fully transparent (the pure-integer
//   path). The shift is arithmetic when IS_SIGNED, logical otherwise.
//
//   Built as a binary tree of align_cell_bfp cells: level l pairs adjacent
//   groups of 2**l input bundles; an odd group count leaves a bye group that
//   passes through unshifted and pairs at a later level (the cell's
//   asymmetric SIZE_0/SIZE_1 absorbs the unequal group sizes). Because
//   truncating right shifts compose exactly, the cascaded per-level shifts
//   are bit-identical to a single flat shift to the global max. NUM_EXP = 1
//   degenerates to a pass-through.
//
//   The cells' lane-fusion chains are tied off here (fused H/L lane pairs
//   instantiate align_cell_bfp directly). The parent is responsible for
//   presenting the minimum exponent on a zeroed/idle bundle so it never wins
//   the max.
//
// Parameters:
//   WIDTH     - row width
//   SIZE      - number of rows per bundle (share one exponent)
//   NUM_EXP   - number of bundles/exponents to align
//   EXP_WIDTH - exponent width (unsigned)
//   IS_SIGNED - 1: arithmetic (sign-fill) right shift, 0: logical
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module align_bfp #(
    parameter  int WIDTH     = 20,
    parameter  int SIZE      = 1,
    parameter  int NUM_EXP   = 8,
    parameter  int EXP_WIDTH = 8,
    parameter  bit IS_SIGNED = 1'b1,
    localparam int TOTAL     = NUM_EXP * SIZE,
    localparam int LEVELS    = (NUM_EXP > 1) ? $clog2(NUM_EXP) : 0
)(
    input  logic [    WIDTH-1:0] in_i  [0:NUM_EXP-1][0:SIZE-1],
    input  logic [EXP_WIDTH-1:0] exp_i [0:NUM_EXP-1],
    output logic [    WIDTH-1:0] out_o [0:TOTAL-1],
    output logic [EXP_WIDTH-1:0] exp_o
);

    logic [WIDTH-1:0] lvl_row [0:LEVELS][0:TOTAL-1] /* verilator split_var */;

    /* verilator lint_off UNUSEDSIGNAL */
    logic [EXP_WIDTH-1:0] lvl_exp [0:LEVELS][0:NUM_EXP-1] /* verilator split_var */;
    /* verilator lint_on UNUSEDSIGNAL */

    genvar k, j, l;
    generate
        for (k = 0; k < NUM_EXP; k++) begin : gen_flatten
            for (j = 0; j < SIZE; j++) begin : gen_row
                assign lvl_row[0][k*SIZE+j] = in_i[k][j];
            end
            assign lvl_exp[0][k] = exp_i[k];
        end

        for (l = 0; l < LEVELS; l++) begin : gen_level
            localparam int SPAN  = 2 ** l;
            localparam int N_IN  = (NUM_EXP + SPAN - 1) / SPAN;
            localparam int PAIRS = N_IN / 2;
            localparam int BYE   = N_IN % 2;
            localparam int N_OUT = PAIRS + BYE;

            for (genvar p = 0; p < PAIRS; p++) begin : gen_pair
                localparam int G_0    = 2 * p;
                localparam int G_1    = 2 * p + 1;
                localparam int BASE_0 = SIZE * G_0 * SPAN;
                localparam int BASE_1 = SIZE * G_1 * SPAN;
                localparam int END_1  = (G_1 + 1) * SPAN;
                localparam int S_0    = SIZE * SPAN;
                localparam int S_1    = SIZE * (((END_1 > NUM_EXP) ? NUM_EXP : END_1) - G_1 * SPAN);

                logic [WIDTH-1:0] cell_in_0 [0:S_0-1];
                logic [WIDTH-1:0] cell_in_1 [0:S_1-1];
                logic [WIDTH-1:0] cell_out  [0:S_0+S_1-1];
                logic [WIDTH-1:0] zero_0    [0:S_0-1];
                logic [WIDTH-1:0] zero_1    [0:S_1-1];

                for (genvar q = 0; q < S_0; q++) begin : gen_bus_0
                    assign cell_in_0[q] = lvl_row[l][BASE_0+q];
                    assign zero_0[q]    = '0;
                end

                for (genvar q = 0; q < S_1; q++) begin : gen_bus_1
                    assign cell_in_1[q] = lvl_row[l][BASE_1+q];
                    assign zero_1[q]    = '0;
                end

                for (genvar q = 0; q < S_0 + S_1; q++) begin : gen_bus_out
                    assign lvl_row[l+1][BASE_0+q] = cell_out[q];
                end

                /* verilator lint_off PINCONNECTEMPTY */
                align_cell_bfp #(
                    .WIDTH    (WIDTH),
                    .SIZE_0   (S_0),
                    .SIZE_1   (S_1),
                    .EXP_WIDTH(EXP_WIDTH),
                    .IS_SIGNED(IS_SIGNED)
                ) align_cell_bfp_i (
                    .in_0_i    (cell_in_0),
                    .exp_0_i   (lvl_exp[l][G_0]),
                    .in_1_i    (cell_in_1),
                    .exp_1_i   (lvl_exp[l][G_1]),
                    .chain_en_i(1'b0),
                    .chain_0_i (zero_0),
                    .chain_1_i (zero_1),
                    .chain_0_o (),
                    .chain_1_o (),
                    .out_o     (cell_out),
                    .exp_o     (lvl_exp[l+1][p])
                );
                /* verilator lint_on PINCONNECTEMPTY */
            end

            if (BYE == 1) begin : gen_bye
                localparam int G_B    = 2 * PAIRS;
                localparam int BASE_B = SIZE * G_B * SPAN;
                localparam int S_B    = SIZE * (NUM_EXP - G_B * SPAN);

                for (genvar q = 0; q < S_B; q++) begin : gen_bus_b
                    assign lvl_row[l+1][BASE_B+q] = lvl_row[l][BASE_B+q];
                end

                assign lvl_exp[l+1][PAIRS] = lvl_exp[l][G_B];
            end

            for (genvar e = N_OUT; e < NUM_EXP; e++) begin : gen_exp_tie
                assign lvl_exp[l+1][e] = '0;
            end
        end

        for (k = 0; k < TOTAL; k++) begin : gen_unflatten
            assign out_o[k] = lvl_row[LEVELS][k];
        end
    endgenerate

    assign exp_o = lvl_exp[LEVELS][0];

endmodule
