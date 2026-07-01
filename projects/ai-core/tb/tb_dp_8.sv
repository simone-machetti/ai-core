// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for dp_8. Drives NUM_RAND random (a, b) vector pairs,
//   each checked under all four per-operand signedness combinations, plus
//   directed corner cases, and verifies two properties of the 18-bit carry-save
//   output:
//     - resolve:        sum_o + carry_o == sum_i(a_i * b_i) modulo 2^18
//     - sign-consistent: signext(sum_o) + signext(carry_o) == sum_i(a_i * b_i)
//   The second guarantees the output can be sign-extended by pe_array downstream.
//   Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random vectors
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_dp_8 #(
    parameter int NUM_RAND = 2000
);

    localparam int LANES     = 8;
    localparam int WIDTH_A   = 8;
    localparam int WIDTH_B   = 4;
    localparam int OUT_WIDTH = 18;

    localparam logic [WIDTH_A-1:0] A_ZERO     = '0;
    localparam logic [WIDTH_A-1:0] A_ALL_ONES = {WIDTH_A{1'b1}};
    localparam logic [WIDTH_A-1:0] A_MAX_POS  = {1'b0, {(WIDTH_A-1){1'b1}}};
    localparam logic [WIDTH_A-1:0] A_MIN_NEG  = {1'b1, {(WIDTH_A-1){1'b0}}};
    localparam logic [WIDTH_B-1:0] B_ZERO     = '0;
    localparam logic [WIDTH_B-1:0] B_ALL_ONES = {WIDTH_B{1'b1}};
    localparam logic [WIDTH_B-1:0] B_MAX_POS  = {1'b0, {(WIDTH_B-1){1'b1}}};
    localparam logic [WIDTH_B-1:0] B_MIN_NEG  = {1'b1, {(WIDTH_B-1){1'b0}}};

    logic [WIDTH_A-1:0]   a_v [0:LANES-1];
    logic [WIDTH_B-1:0]   b_v [0:LANES-1];
    logic                 is_signed_a;
    logic                 is_signed_b;
    logic [OUT_WIDTH-1:0] sum;
    logic [OUT_WIDTH-1:0] carry;

    dp_8 dp_8_i (
        .a_i          (a_v),
        .b_i          (b_v),
        .is_signed_a_i(is_signed_a),
        .is_signed_b_i(is_signed_b),
        .sum_o        (sum),
        .carry_o      (carry)
    );

    task automatic check(input bit sgn_a, input bit sgn_b);
        longint               exp;
        longint               mask;
        logic [OUT_WIDTH-1:0] res;
        is_signed_a = sgn_a;
        is_signed_b = sgn_b;
        #1;
        exp  = 0;
        mask = (longint'(1) << OUT_WIDTH) - 1;
        for (int i = 0; i < LANES; i++) begin
            longint a_val;
            longint b_val;
            a_val = sgn_a ? longint'($signed(a_v[i])) : longint'($unsigned(a_v[i]));
            b_val = sgn_b ? longint'($signed(b_v[i])) : longint'($unsigned(b_v[i]));
            exp  += a_val * b_val;
        end
        res = sum + carry;
        if (res !== OUT_WIDTH'(exp & mask)) begin
            $dumpoff;
            $error("RESOLVE MISMATCH sa=%0d sb=%0d exp=%0d got=%0d (sum=%0d carry=%0d)",
                   sgn_a, sgn_b, exp, res, sum, carry);
            $fatal;
        end
        if ((longint'($signed(sum)) + longint'($signed(carry))) !== exp) begin
            $dumpoff;
            $error("SIGN-EXTEND MISMATCH sa=%0d sb=%0d exp=%0d (sum=%0d carry=%0d): not sign-consistent",
                   sgn_a, sgn_b, exp, $signed(sum), $signed(carry));
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
        for (int i = 0; i < LANES; i++) begin
            a_v[i] = WIDTH_A'($urandom);
            b_v[i] = WIDTH_B'($urandom);
        end
    endtask

    task automatic set_vec(input logic [WIDTH_A-1:0] av, input logic [WIDTH_B-1:0] bv);
        for (int i = 0; i < LANES; i++) begin
            a_v[i] = av;
            b_v[i] = bv;
        end
    endtask

    initial begin
        $display("\nStarting dp_8 verification (LANES=%0d WIDTH_A=%0d WIDTH_B=%0d OUT_WIDTH=%0d)...\n",
                 LANES, WIDTH_A, WIDTH_B, OUT_WIDTH);
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_dp_8.dp_8_i);

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

        $dumpoff;
        $display("dp_8: all %0d random + corner tests PASSED!\n", NUM_RAND);
        $finish;
    end

endmodule
