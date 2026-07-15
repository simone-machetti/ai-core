// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for dp_8_sqr. Drives NUM_RAND random vectors plus
//   directed corners and checks the carry-save square-sum against a golden that
//   does the same computation. Inputs are the *pre-centered* signed nibbles the
//   dispatcher would produce, so every nibble is generated directly in [-8,7]
//   (no is_signed, no -8 bias here). For each lane a_i packs two signed nibbles
//   {AH, AL} and b_i is one signed nibble; the golden is
//       S_DP8 = sum_k [ 16*(AH_k+b_k)^2 + (AL_k+b_k)^2 ]
//   and the test requires sum_o + carry_o == S_DP8 (mod 2^18, exact since
//   S_DP8 <= 34816). The output is non-negative, so there is no sign-consistency
//   check. Nibbles are biased toward the extremes (-8, +7) to hit the
//   square-argument corner -16 (square 256, the 9th output bit). Reports a fatal
//   error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random vectors
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_dp_8_sqr #(
    parameter int NUM_RAND = 2000
);

    localparam int LANES     = 8;
    localparam int WIDTH_A   = 8;
    localparam int WIDTH_B   = 4;
    localparam int NIB       = 4;
    localparam int OUT_WIDTH = 18;

    localparam logic [NIB-1:0] N_MIN  = 4'b1000;
    localparam logic [NIB-1:0] N_MAX  = 4'b0111;
    localparam logic [NIB-1:0] N_ZERO = 4'b0000;

    logic [WIDTH_A-1:0]   a_v [0:LANES-1];
    logic [WIDTH_B-1:0]   b_v [0:LANES-1];
    logic [OUT_WIDTH-1:0] sum;
    logic [OUT_WIDTH-1:0] carry;

    dp_8_sqr dp_8_sqr_i (
        .a_i    (a_v),
        .b_i    (b_v),
        .sum_o  (sum),
        .carry_o(carry)
    );

    function automatic logic [NIB-1:0] rand_nib;
        int p;
        p = $urandom % 5;
        if      (p == 0) rand_nib = N_MIN;
        else if (p == 1) rand_nib = N_MAX;
        else             rand_nib = NIB'($urandom);
    endfunction

    task automatic check;
        longint               exp;
        logic [OUT_WIDTH-1:0] res;
        #1;
        exp = 0;
        for (int k = 0; k < LANES; k++) begin
            longint ah, al, b, s_ah, s_al;
            ah   = longint'($signed(a_v[k][NIB +: NIB]));
            al   = longint'($signed(a_v[k][  0 +: NIB]));
            b    = longint'($signed(b_v[k]));
            s_ah = ah + b;
            s_al = al + b;
            exp += 16 * (s_ah * s_ah) + (s_al * s_al);
        end
        res = sum + carry;
        if (res !== OUT_WIDTH'(exp)) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("MISMATCH exp=%0d got=%0d (sum=%0d carry=%0d)", exp, res, sum, carry);
            $fatal;
        end
    endtask

    task automatic rand_vec;
        for (int k = 0; k < LANES; k++) begin
            a_v[k] = {rand_nib(), rand_nib()};
            b_v[k] = rand_nib();
        end
    endtask

    task automatic set_vec(input logic [NIB-1:0] ah,
                           input logic [NIB-1:0] al,
                           input logic [NIB-1:0] b);
        for (int k = 0; k < LANES; k++) begin
            a_v[k] = {ah, al};
            b_v[k] = b;
        end
    endtask

    initial begin
        $display("\nStarting dp_8_sqr verification (LANES=%0d OUT_WIDTH=%0d NUM_RAND=%0d)...\n",
                 LANES, OUT_WIDTH, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_dp_8_sqr.dp_8_sqr_i);
`endif

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_vec;
            check;
        end

        for (int c = 0; c < 8; c++) begin
            set_vec(c[2] ? N_MAX : N_MIN, c[1] ? N_MAX : N_MIN, c[0] ? N_MAX : N_MIN);
            check;
        end
        set_vec(N_ZERO, N_ZERO, N_ZERO);
        check;

`ifdef VCD
        $dumpoff;
`endif
        $display("dp_8_sqr: all %0d random + corner tests PASSED!\n", NUM_RAND);
        $finish;
    end

endmodule
