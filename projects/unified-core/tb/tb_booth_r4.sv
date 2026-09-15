// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for booth_r4. Drives NUM_RAND random (a, b) vectors,
//   each checked under all four per-operand signedness combinations, plus
//   directed corner cases, and verifies that the weighted sum of the partial
//   products equals a * b, i.e. sum_i(pp_o[i] * 4^i) == a_val * b_val where a_val
//   and b_val take a and b as signed or unsigned per is_signed_a_i / is_signed_b_i.
//   Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   IN_WIDTH_A - bit width of the multiplicand a (forwarded to the DUT)
//   IN_WIDTH_B - bit width of the multiplier b (forwarded to the DUT)
//   NUM_RAND   - number of random vectors
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_booth_r4 #(
    parameter int IN_WIDTH_A = 8,
    parameter int IN_WIDTH_B = 4,
    parameter int NUM_RAND   = 2000
);

    localparam int PP_SIZE  = IN_WIDTH_B / 2 + 1;
    localparam int PP_WIDTH = IN_WIDTH_A + 2;

    localparam logic [IN_WIDTH_A-1:0] A_ZERO     = '0;
    localparam logic [IN_WIDTH_A-1:0] A_ALL_ONES = {IN_WIDTH_A{1'b1}};
    localparam logic [IN_WIDTH_A-1:0] A_MAX_POS  = {1'b0, {(IN_WIDTH_A-1){1'b1}}};
    localparam logic [IN_WIDTH_A-1:0] A_MIN_NEG  = {1'b1, {(IN_WIDTH_A-1){1'b0}}};
    localparam logic [IN_WIDTH_B-1:0] B_ZERO     = '0;
    localparam logic [IN_WIDTH_B-1:0] B_ALL_ONES = {IN_WIDTH_B{1'b1}};
    localparam logic [IN_WIDTH_B-1:0] B_MAX_POS  = {1'b0, {(IN_WIDTH_B-1){1'b1}}};
    localparam logic [IN_WIDTH_B-1:0] B_MIN_NEG  = {1'b1, {(IN_WIDTH_B-1){1'b0}}};

    logic [IN_WIDTH_A-1:0] a_v;
    logic [IN_WIDTH_B-1:0] b_v;
    logic                  is_signed_a;
    logic                  is_signed_b;
    logic [ PP_WIDTH-1:0]  pp [0:PP_SIZE-1];

    booth_r4 #(
        .IN_WIDTH_A(IN_WIDTH_A),
        .IN_WIDTH_B(IN_WIDTH_B)
    ) booth_r4_i (
        .a_i          (a_v),
        .b_i          (b_v),
        .is_signed_a_i(is_signed_a),
        .is_signed_b_i(is_signed_b),
        .pp_o         (pp)
    );

    task automatic check(input bit sgn_a, input bit sgn_b);
        longint a_val;
        longint b_val;
        longint prod;
        longint pp_sum;
        is_signed_a = sgn_a;
        is_signed_b = sgn_b;
        #1;
        a_val  = sgn_a ? longint'($signed(a_v)) : longint'($unsigned(a_v));
        b_val  = sgn_b ? longint'($signed(b_v)) : longint'($unsigned(b_v));
        prod   = a_val * b_val;
        pp_sum = 0;
        for (int i = 0; i < PP_SIZE; i++) begin
            pp_sum += longint'($signed(pp[i])) * (longint'(1) << (2 * i));
        end
        if (pp_sum !== prod) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("MISMATCH sgn_a=%0d sgn_b=%0d a=%0d b=%0d prod=%0d pp_sum=%0d",
                   sgn_a, sgn_b, a_val, b_val, prod, pp_sum);
            $fatal;
        end
    endtask

    task automatic check_all;
        check(1'b0, 1'b0);
        check(1'b0, 1'b1);
        check(1'b1, 1'b0);
        check(1'b1, 1'b1);
    endtask

    task automatic rand_vec;
        a_v = IN_WIDTH_A'($urandom);
        b_v = IN_WIDTH_B'($urandom);
    endtask

    task automatic set_vec(input logic [IN_WIDTH_A-1:0] av, input logic [IN_WIDTH_B-1:0] bv);
        a_v = av;
        b_v = bv;
    endtask

    initial begin
        $display("\nStarting booth_r4 verification (IN_WIDTH_A=%0d IN_WIDTH_B=%0d PP_SIZE=%0d)...\n",
                 IN_WIDTH_A, IN_WIDTH_B, PP_SIZE);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_booth_r4.booth_r4_i);
`endif

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_vec;
            check_all;
        end

        set_vec(A_ZERO, B_ZERO);
        check_all;
        set_vec(A_MAX_POS, B_MAX_POS);
        check_all;
        set_vec(A_MIN_NEG, B_MIN_NEG);
        check_all;
        set_vec(A_MAX_POS, B_MIN_NEG);
        check_all;
        set_vec(A_MIN_NEG, B_MAX_POS);
        check_all;
        set_vec(A_ALL_ONES, B_ALL_ONES);
        check_all;

`ifdef VCD
        $dumpoff;
`endif
        $display("booth_r4: all %0d random + corner tests PASSED!\n", NUM_RAND);
        $finish;
    end

endmodule
