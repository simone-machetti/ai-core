// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for cpr_c_n. Drives NUM_RAND random input vectors
//   (extended per the compile-time IS_SIGNED) plus directed corner cases, and
//   verifies that sum_o + carry_o equals the arithmetic sum of the inputs
//   (modulo 2^OUT_WIDTH). Reports a fatal error on any mismatch. Dumps
//   activity.vcd. Run once per signedness (IS_SIGNED=1 / IS_SIGNED=0).
//
// Parameters:
//   IN_WIDTH  - bit width of each input word (forwarded to the DUT)
//   IN_SIZE   - number of input words (forwarded to the DUT)
//   IS_SIGNED - input signedness (forwarded to the DUT)
//   NUM_RAND  - number of random vectors
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_cpr_c_n #(
    parameter int IN_WIDTH  = 8,
    parameter int IN_SIZE   = 8,
    parameter bit IS_SIGNED = 1'b1,
    parameter int NUM_RAND  = 2000
);

    localparam int EXT       = $clog2(IN_SIZE);
    localparam int OUT_WIDTH = IN_WIDTH + EXT;

    localparam logic [IN_WIDTH-1:0] ZERO     = '0;
    localparam logic [IN_WIDTH-1:0] ALL_ONES = {IN_WIDTH{1'b1}};
    localparam logic [IN_WIDTH-1:0] MAX_POS  = {1'b0, {(IN_WIDTH-1){1'b1}}};
    localparam logic [IN_WIDTH-1:0] MIN_NEG  = {1'b1, {(IN_WIDTH-1){1'b0}}};

    logic [ IN_WIDTH-1:0] in_v [0:IN_SIZE-1];
    logic [OUT_WIDTH-1:0] sum;
    logic [OUT_WIDTH-1:0] carry;

    cpr_c_n #(
        .IN_WIDTH (IN_WIDTH),
        .IN_SIZE  (IN_SIZE),
        .IS_SIGNED(IS_SIGNED)
    ) cpr_c_n_i (
        .in_i   (in_v),
        .sum_o  (sum),
        .carry_o(carry)
    );

    task automatic check;
        longint               exp;
        longint               mask;
        logic [OUT_WIDTH-1:0] res;
        #1;
        exp  = 0;
        mask = (longint'(1) << OUT_WIDTH) - 1;
        for (int i = 0; i < IN_SIZE; i++) begin
            if (IS_SIGNED) exp += longint'($signed(in_v[i]));
            else           exp += longint'($unsigned(in_v[i]));
        end
        res = sum + carry;
        if (res !== OUT_WIDTH'(exp & mask)) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("MISMATCH is_signed=%0d exp=%0d got=%0d (sum=%0d carry=%0d)",
                   IS_SIGNED, exp, res, sum, carry);
            $fatal;
        end
    endtask

    task automatic rand_vec;
        for (int i = 0; i < IN_SIZE; i++) in_v[i] = IN_WIDTH'($urandom);
    endtask

    task automatic set_vec(input logic [IN_WIDTH-1:0] val);
        for (int i = 0; i < IN_SIZE; i++) in_v[i] = val;
    endtask

    initial begin
        $display("\nStarting cpr_c_n verification (IN_WIDTH=%0d IN_SIZE=%0d IS_SIGNED=%0d OUT_WIDTH=%0d)...\n",
                 IN_WIDTH, IN_SIZE, IS_SIGNED, OUT_WIDTH);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_cpr_c_n.cpr_c_n_i);
`endif

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_vec;
            check();
        end

        set_vec(ZERO);
        check();
        set_vec(ALL_ONES);
        check();
        set_vec(MAX_POS);
        check();
        set_vec(MIN_NEG);
        check();

`ifdef VCD
        $dumpoff;
`endif
        $display("cpr_c_n: all %0d random + corner tests PASSED!\n", NUM_RAND);
        $finish;
    end

endmodule
