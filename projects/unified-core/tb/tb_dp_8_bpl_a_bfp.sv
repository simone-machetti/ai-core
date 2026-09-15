// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for dp_8_bpl_a_bfp. Drives NUM_RAND random (a, b)
//   vector pairs, each checked under all four per-operand signedness
//   combinations, plus directed corner cases. The bench owns the dispatcher-side
//   operand preparation - it derives the 5-bit exact values and the 6-bit pair
//   sums from the raw 4-bit nibbles exactly as gate_n_bpl_bfp does - so the
//   DUT is exercised through the same contract it sees in the grid.
//
//   Three properties are verified on every vector:
//     - resolve:        sum_o + carry_o == sum_k(a_k * b_k) modulo 2^OUT_WIDTH
//     - sign-consistent: signext(sum_o) + signext(carry_o) == sum_k(a_k * b_k)
//     - equivalence:    the value equals that of a dp_8 fed the same raw operands
//   The second is the gating property: the L2 stage sits 6% inside the
//   conservative 2^(W-1) > sum|rows| bound, so its sign-consistency is
//   established here rather than by construction. Lanes are therefore biased
//   toward the extreme values (most-negative / max-positive / all-ones) so the
//   rare corners are reached; a uniform distribution needs far more vectors.
//   Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random vectors (each checked in 4 signedness combos)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_dp_8_bpl_a_bfp #(
    parameter int NUM_RAND = 2000
);

    localparam int LANES     = 8;
    localparam int WIDTH_A   = 8;
    localparam int WIDTH_B   = 4;
    localparam int B_WIDTH   = WIDTH_B + 1;
    localparam int SUM_WIDTH = WIDTH_B + 2;
    localparam int NUM_BLK   = LANES / 2;
    localparam int OUT_WIDTH = 22;
    localparam int REF_WIDTH = 20;

    localparam logic [WIDTH_A-1:0] A_ZERO     = '0;
    localparam logic [WIDTH_A-1:0] A_ALL_ONES = {WIDTH_A{1'b1}};
    localparam logic [WIDTH_A-1:0] A_MAX_POS  = {1'b0, {(WIDTH_A-1){1'b1}}};
    localparam logic [WIDTH_A-1:0] A_MIN_NEG  = {1'b1, {(WIDTH_A-1){1'b0}}};
    localparam logic [WIDTH_B-1:0] B_ZERO     = '0;
    localparam logic [WIDTH_B-1:0] B_ALL_ONES = {WIDTH_B{1'b1}};
    localparam logic [WIDTH_B-1:0] B_MAX_POS  = {1'b0, {(WIDTH_B-1){1'b1}}};
    localparam logic [WIDTH_B-1:0] B_MIN_NEG  = {1'b1, {(WIDTH_B-1){1'b0}}};

    logic [  WIDTH_A-1:0] a_v     [  0:LANES-1];
    logic [  WIDTH_B-1:0] b_nib   [  0:LANES-1];
    logic [  B_WIDTH-1:0] b_v     [  0:LANES-1];
    logic [SUM_WIDTH-1:0] b_sum_v [0:NUM_BLK-1];
    logic                 is_signed_a;
    logic                 is_signed_b;
    logic [OUT_WIDTH-1:0] sum;
    logic [OUT_WIDTH-1:0] carry;
    logic [REF_WIDTH-1:0] ref_sum;
    logic [REF_WIDTH-1:0] ref_carry;

    dp_8_bpl_a_bfp dp_8_bpl_a_bfp_i (
        .a_i          (a_v),
        .b_i          (b_v),
        .b_sum_i      (b_sum_v),
        .is_signed_a_i(is_signed_a),
        .sum_o        (sum),
        .carry_o      (carry)
    );

    dp_8 dp_8_i (
        .a_i          (a_v),
        .b_i          (b_nib),
        .is_signed_a_i(is_signed_a),
        .is_signed_b_i(is_signed_b),
        .sum_o        (ref_sum),
        .carry_o      (ref_carry)
    );

    task automatic check(input bit sgn_a, input bit sgn_b);
        longint               exp;
        longint               mask;
        logic [OUT_WIDTH-1:0] res;
        is_signed_a = sgn_a;
        is_signed_b = sgn_b;
        for (int k = 0; k < LANES; k++) begin
            b_v[k] = {sgn_b & b_nib[k][WIDTH_B-1], b_nib[k]};
        end
        for (int j = 0; j < NUM_BLK; j++) begin
            b_sum_v[j] = SUM_WIDTH'(SUM_WIDTH'($signed(b_v[2*j+0])) +
                                    SUM_WIDTH'($signed(b_v[2*j+1])));
        end
        #1;
        exp  = 0;
        mask = (longint'(1) << OUT_WIDTH) - 1;
        for (int i = 0; i < LANES; i++) begin
            longint a_val;
            longint b_val;
            a_val = sgn_a ? longint'($signed(a_v[i]))   : longint'($unsigned(a_v[i]));
            b_val = sgn_b ? longint'($signed(b_nib[i])) : longint'($unsigned(b_nib[i]));
            exp  += a_val * b_val;
        end
        res = sum + carry;
        if (res !== OUT_WIDTH'(exp & mask)) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("RESOLVE MISMATCH sa=%0d sb=%0d exp=%0d got=%0d (sum=%0d carry=%0d)",
                   sgn_a, sgn_b, exp, res, sum, carry);
            $fatal;
        end
        if ((longint'($signed(sum)) + longint'($signed(carry))) !== exp) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("SIGN-EXTEND MISMATCH sa=%0d sb=%0d exp=%0d (sum=%0d carry=%0d): not sign-consistent",
                   sgn_a, sgn_b, exp, $signed(sum), $signed(carry));
            $fatal;
        end
        if ((longint'($signed(sum)) + longint'($signed(carry))) !==
            (longint'($signed(ref_sum)) + longint'($signed(ref_carry)))) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("DP8 EQUIVALENCE MISMATCH sa=%0d sb=%0d bpl=%0d dp_8=%0d",
                   sgn_a, sgn_b, longint'($signed(sum)) + longint'($signed(carry)),
                   longint'($signed(ref_sum)) + longint'($signed(ref_carry)));
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
        int pa, pb;
        for (int i = 0; i < LANES; i++) begin
            pa = $urandom % 5;
            pb = $urandom % 5;
            a_v[i]   = (pa == 0) ? A_MIN_NEG : (pa == 1) ? A_MAX_POS : WIDTH_A'($urandom);
            b_nib[i] = (pb == 0) ? B_MIN_NEG : (pb == 1) ? B_MAX_POS : WIDTH_B'($urandom);
        end
    endtask

    task automatic set_vec(input logic [WIDTH_A-1:0] av, input logic [WIDTH_B-1:0] bv);
        for (int i = 0; i < LANES; i++) begin
            a_v[i]   = av;
            b_nib[i] = bv;
        end
    endtask

    initial begin
        $display("\nStarting dp_8_bpl_a_bfp verification (LANES=%0d WIDTH_A=%0d WIDTH_B=%0d OUT_WIDTH=%0d)...\n",
                 LANES, WIDTH_A, WIDTH_B, OUT_WIDTH);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_dp_8_bpl_a_bfp.dp_8_bpl_a_bfp_i);
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
        set_vec(A_ALL_ONES, B_MIN_NEG);
        check_all;
        set_vec(A_MIN_NEG, B_ALL_ONES);
        check_all;
        set_vec(A_MAX_POS, B_ZERO);
        check_all;
        set_vec(A_MIN_NEG, B_ZERO);
        check_all;
        set_vec(A_ALL_ONES, B_ZERO);
        check_all;
        set_vec(A_ZERO, B_MAX_POS);
        check_all;
        set_vec(A_ZERO, B_MIN_NEG);
        check_all;
        set_vec(A_ZERO, B_ALL_ONES);
        check_all;

`ifdef VCD
        $dumpoff;
`endif
        $display("dp_8_bpl_a_bfp: all %0d random + corner tests PASSED!\n", NUM_RAND);
        $finish;
    end

endmodule
