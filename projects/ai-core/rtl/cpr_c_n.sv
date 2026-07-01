// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Parameterized N-to-2 carry-save compressor, cascade build. Reduces IN_SIZE
//   input words, each IN_WIDTH bits wide, to two outputs (sum_o, carry_o) whose
//   arithmetic sum equals the sum of all inputs (modulo 2^OUT_WIDTH). Each input
//   is first extended by EXT bits to OUT_WIDTH = IN_WIDTH + EXT (sign-extended
//   when IS_SIGNED, otherwise zero-extended). The running carry-save pair is
//   seeded from the first two extended inputs (any two numbers already form a
//   carry-save pair), then the remaining inputs are absorbed one at a time
//   through a cascade of 3:2 carry-save stages, each a row of full adders (fa)
//   whose carry row is shifted up by one position - IN_SIZE-2 stages in all.
//   Minimal area; latency grows linearly with IN_SIZE. EXT defaults to
//   ceil(log2(IN_SIZE)).
//
// Parameters:
//   IN_WIDTH  - bit width of each input word
//   IN_SIZE   - number of input words to compress
//   EXT       - extra bits added on top of IN_WIDTH (default ceil(log2(IN_SIZE)))
//   IS_SIGNED - input extension: 1 = sign-extend, 0 = zero-extend
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module cpr_c_n #(
    parameter int IN_WIDTH  = 8,
    parameter int IN_SIZE   = 8,
    parameter int EXT       = $clog2(IN_SIZE),
    parameter bit IS_SIGNED = 1'b1,

    localparam int OUT_WIDTH = IN_WIDTH + EXT,
    localparam int NSTAGE    = (IN_SIZE >= 2) ? (IN_SIZE - 2) : 0
)(
    input  logic [ IN_WIDTH-1:0] in_i [0:IN_SIZE-1],
    output logic [OUT_WIDTH-1:0] sum_o,
    output logic [OUT_WIDTH-1:0] carry_o
);

    logic [OUT_WIDTH-1:0] ext_in [0:IN_SIZE-1];
    logic [OUT_WIDTH-1:0] s      [0:NSTAGE];
    logic [OUT_WIDTH-1:0] c      [0:NSTAGE];

    genvar i, k, b;

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
        if (IN_SIZE == 1) begin : gen_seed_one
            assign s[0] = ext_in[0];
            assign c[0] = '0;
        end else begin : gen_seed_two
            assign s[0] = ext_in[0];
            assign c[0] = ext_in[1];
        end
    endgenerate

    generate
        for (k = 1; k <= NSTAGE; k++) begin : gen_stage
            logic [OUT_WIDTH-1:0] cout;
            for (b = 0; b < OUT_WIDTH; b++) begin : gen_bit
                fa fa_i (
                    .in_0_i(s[k-1][b]),
                    .in_1_i(c[k-1][b]),
                    .cin_i (ext_in[k+1][b]),
                    .sum_o (s[k][b]),
                    .cout_o(cout[b])
                );
            end
            assign c[k] = cout << 1;
        end
    endgenerate

    assign sum_o   = s[NSTAGE];
    assign carry_o = c[NSTAGE];

endmodule
