// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized N-to-2 carry-save compressor, Wallace-tree build. Reduces
//   IN_SIZE input words, each IN_WIDTH bits wide, to two outputs (sum_o,
//   carry_o) whose arithmetic sum equals the sum of all inputs (modulo
//   2^OUT_WIDTH). Each input is first extended by EXT bits to OUT_WIDTH =
//   IN_WIDTH + EXT (sign-extended when IS_SIGNED, otherwise zero-extended).
//   The IN_SIZE rows are then reduced in parallel layers: each layer splits the
//   current rows into disjoint groups of three and compresses each group to two
//   with a row of full adders (fa) whose carry row is shifted up by one
//   position, passing any one or two leftover rows through unchanged, until two
//   rows remain. Logarithmic depth (~log_1.5(IN_SIZE)) to maximize throughput.
//   EXT defaults to ceil(log2(IN_SIZE)).
//
// Parameters:
//   IN_WIDTH  - bit width of each input word
//   IN_SIZE   - number of input words to compress
//   EXT       - extra bits added on top of IN_WIDTH (default ceil(log2(IN_SIZE)))
//   IS_SIGNED - input extension: 1 = sign-extend, 0 = zero-extend
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNOPTFLAT */

module cpr_w_n #(
    parameter int IN_WIDTH  = 8,
    parameter int IN_SIZE   = 8,
    parameter int EXT       = $clog2(IN_SIZE),
    parameter bit IS_SIGNED = 1'b1,

    localparam int OUT_WIDTH = IN_WIDTH + EXT
)(
    input  logic [ IN_WIDTH-1:0] in_i [0:IN_SIZE-1],
    output logic [OUT_WIDTH-1:0] sum_o,
    output logic [OUT_WIDTH-1:0] carry_o
);

    function automatic int next_rows(input int n);
        return (n / 3) * 2 + (n % 3);
    endfunction

    function automatic int num_layers(input int n);
        int cnt;
        cnt = 0;
        while (n > 2) begin
            n   = next_rows(n);
            cnt = cnt + 1;
        end
        return cnt;
    endfunction

    function automatic int rows_at(input int n0, input int layer);
        int n;
        n = n0;
        for (int l = 0; l < layer; l++) begin
            n = next_rows(n);
        end
        return n;
    endfunction

    localparam int NUM_LAYERS = num_layers(IN_SIZE);

    logic [OUT_WIDTH-1:0] ext_in [0:IN_SIZE-1];
    logic [OUT_WIDTH-1:0] row    [0:NUM_LAYERS][0:IN_SIZE-1];

    genvar i, l, g, b;

    generate
        if (EXT == 0) begin : gen_no_ext
            for (i = 0; i < IN_SIZE; i++) begin : gen_pass
                assign ext_in[i] = in_i[i];
            end
        end else begin : gen_ext
            ext_n #(
                .WIDTH(IN_WIDTH),
                .SIZE (IN_SIZE),
                .EXT  (EXT)
            ) ext_n_i (
                .in_i       (in_i),
                .is_signed_i(IS_SIGNED),
                .out_o      (ext_in)
            );
        end
    endgenerate

    generate
        for (i = 0; i < IN_SIZE; i++) begin : gen_row0
            assign row[0][i] = ext_in[i];
        end
    endgenerate

    generate
        for (l = 0; l < NUM_LAYERS; l++) begin : gen_layer
            localparam int R   = rows_at(IN_SIZE, l);
            localparam int NG  = R / 3;
            localparam int REM = R % 3;
            for (g = 0; g < NG; g++) begin : gen_group
                logic [OUT_WIDTH-1:0] cout;
                for (b = 0; b < OUT_WIDTH; b++) begin : gen_bit
                    fa fa_i (
                        .in_0_i(row[l][3*g+0][b]),
                        .in_1_i(row[l][3*g+1][b]),
                        .cin_i (row[l][3*g+2][b]),
                        .sum_o (row[l+1][2*g+0][b]),
                        .cout_o(cout[b])
                    );
                end
                assign row[l+1][2*g+1] = cout << 1;
            end
            for (g = 0; g < REM; g++) begin : gen_rem
                assign row[l+1][2*NG + g] = row[l][3*NG + g];
            end
        end
    endgenerate

    generate
        if (IN_SIZE == 1) begin : gen_out_one
            assign sum_o   = row[0][0];
            assign carry_o = '0;
        end else begin : gen_out_two
            assign sum_o   = row[NUM_LAYERS][0];
            assign carry_o = row[NUM_LAYERS][1];
        end
    endgenerate

endmodule

/* verilator lint_on UNOPTFLAT */
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
