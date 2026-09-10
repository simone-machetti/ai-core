// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for dp_8_nr4sd_bfp, the 2-partial-product DP8. The
//   DUT consumes per-lane digit codes, so the bench owns the dispatcher-side
//   operand preparation and exercises the core through the same contract it sees
//   in the grid, in two ways:
//
//     recoded lanes - NUM_RAND random (a, b, c_in) vectors: each 4-bit b lane is
//                     recoded by a software model written from the ARITHMETIC
//                     definition of the hybrid (NR4SD+ low pair: s = raw + c_in,
//                     emit s-4 and a carry when s >= 3; Booth top pair: the pair
//                     read as signed plus that carry), never from the boolean
//                     equations nr4sd_r4 implements, and the digits are packed
//                     into codes by value tables. The golden is
//                     sum_k(a_k * (signed(b_k) + c_in_k)) - the cross-nibble carry
//                     is the +1, and c_in is drawn per lane so both link states are
//                     exercised together with the sign of every nibble.
//     raw code space - NUM_RAND random (a, code, window) vectors: every 2-bit
//                     NR4SD+ code and every 3-bit Booth window is legal, so the
//                     bench also drives the code space directly, biased toward
//                     the extreme digits (+2 with +2, -1 with -2), and checks
//                     sum_k(a_k * (digit0_k + 4*digit1_k)) over the full [-9,+10]
//                     lane range - values no real nibble produces.
//
//   Two properties are verified on every vector, under both a signednesses:
//     - resolve:         sum_o + carry_o == golden modulo 2^OUT_WIDTH
//     - sign-consistent: signext(sum_o) + signext(carry_o) == golden
//   The second is the gating property: the reduction tree sign-extends and
//   re-aligns the pair, so a merely resolving output is not enough. There is no
//   standalone equivalence against dp_8: an unsigned nibble is not representable
//   by a lone 2-digit DP8 (its DP8 is off by -16*b3*A by design), so equivalence
//   with the Booth baseline is checked one level up, in tb_pe_array_nr4sd_bfp,
//   where the nibbles of an element have been recombined.
//
//   Lanes are biased toward the extreme values (most-negative / max-positive /
//   all-ones) so the compressor guard bits are exercised at their bounds.
//   Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random vectors per experiment (each checked in 2 a-signedness states)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_dp_8_nr4sd_bfp #(
    parameter int NUM_RAND = 2000
);

    localparam int LANES      = 8;
    localparam int WIDTH_A    = 8;
    localparam int WIDTH_B    = 4;
    localparam int CODE_WIDTH = 2;
    localparam int SEL_WIDTH  = 3;
    localparam int OUT_WIDTH  = 20;

    localparam logic [WIDTH_A-1:0] A_ZERO     = '0;
    localparam logic [WIDTH_A-1:0] A_ALL_ONES = {WIDTH_A{1'b1}};
    localparam logic [WIDTH_A-1:0] A_MAX_POS  = {1'b0, {(WIDTH_A-1){1'b1}}};
    localparam logic [WIDTH_A-1:0] A_MIN_NEG  = {1'b1, {(WIDTH_A-1){1'b0}}};
    localparam logic [WIDTH_B-1:0] B_ZERO     = '0;
    localparam logic [WIDTH_B-1:0] B_ALL_ONES = {WIDTH_B{1'b1}};
    localparam logic [WIDTH_B-1:0] B_MAX_POS  = {1'b0, {(WIDTH_B-1){1'b1}}};
    localparam logic [WIDTH_B-1:0] B_MIN_NEG  = {1'b1, {(WIDTH_B-1){1'b0}}};

    logic [   WIDTH_A-1:0] a_v     [0:LANES-1];
    logic [   WIDTH_B-1:0] b_nib   [0:LANES-1];
    logic                  c_in    [0:LANES-1];
    logic [CODE_WIDTH-1:0] b_nr4sd [0:LANES-1];
    logic [ SEL_WIDTH-1:0] b_booth [0:LANES-1];
    logic                  is_signed_a;
    logic [ OUT_WIDTH-1:0] sum;
    logic [ OUT_WIDTH-1:0] carry;

    dp_8_nr4sd_bfp dp_8_nr4sd_bfp_i (
        .a_i          (a_v),
        .b_nr4sd_i    (b_nr4sd),
        .b_booth_i    (b_booth),
        .is_signed_a_i(is_signed_a),
        .sum_o        (sum),
        .carry_o      (carry)
    );

    function automatic logic [CODE_WIDTH-1:0] enc_nr4sd(input int d);
        case (d)
            0:       enc_nr4sd = 2'b00;
            1:       enc_nr4sd = 2'b01;
            2:       enc_nr4sd = 2'b10;
            default: enc_nr4sd = 2'b11;
        endcase
    endfunction

    function automatic logic [SEL_WIDTH-1:0] enc_booth(input int d);
        case (d)
            0:       enc_booth = 3'b000;
            1:       enc_booth = ($urandom % 2) ? 3'b001 : 3'b010;
            2:       enc_booth = 3'b011;
            -1:      enc_booth = ($urandom % 2) ? 3'b101 : 3'b110;
            default: enc_booth = 3'b100;
        endcase
    endfunction

    function automatic longint dec_nr4sd(input logic [CODE_WIDTH-1:0] code);
        case (code)
            2'b00:   dec_nr4sd =  0;
            2'b01:   dec_nr4sd =  1;
            2'b10:   dec_nr4sd =  2;
            default: dec_nr4sd = -1;
        endcase
    endfunction

    function automatic longint dec_booth(input logic [SEL_WIDTH-1:0] w);
        dec_booth = -2 * longint'(w[2]) + longint'(w[1]) + longint'(w[0]);
    endfunction

    task automatic recode(input logic [WIDTH_B-1:0] b, input bit cin,
                          output logic [CODE_WIDTH-1:0] code0, output logic [SEL_WIDTH-1:0] sel1);
        int s;
        int d0;
        int c1;
        int d1;
        s = int'({b[1], b[0]}) + int'(cin);
        if (s >= 3) begin
            d0 = s - 4;
            c1 = 1;
        end else begin
            d0 = s;
            c1 = 0;
        end
        d1    = -2 * int'(b[3]) + int'(b[2]) + c1;
        code0 = enc_nr4sd(d0);
        sel1  = enc_booth(d1);
    endtask

    task automatic check_value(input bit sgn_a, input longint exp, input string tag);
        longint               mask;
        logic [OUT_WIDTH-1:0] res;
        #1;
        mask = (longint'(1) << OUT_WIDTH) - 1;
        res  = sum + carry;
        if (res !== OUT_WIDTH'(exp & mask)) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("%s RESOLVE MISMATCH sa=%0d exp=%0d got=%0d (sum=%0d carry=%0d)",
                   tag, sgn_a, exp, res, sum, carry);
            $fatal;
        end
        if ((longint'($signed(sum)) + longint'($signed(carry))) !== exp) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("%s SIGN-EXTEND MISMATCH sa=%0d exp=%0d (sum=%0d carry=%0d): not sign-consistent",
                   tag, sgn_a, exp, $signed(sum), $signed(carry));
            $fatal;
        end
    endtask

    function automatic longint a_val(input int i, input bit sgn_a);
        return sgn_a ? longint'($signed(a_v[i])) : longint'($unsigned(a_v[i]));
    endfunction

    task automatic check_recoded(input bit sgn_a);
        longint exp;
        is_signed_a = sgn_a;
        for (int k = 0; k < LANES; k++) recode(b_nib[k], c_in[k], b_nr4sd[k], b_booth[k]);
        exp = 0;
        for (int i = 0; i < LANES; i++)
            exp += a_val(i, sgn_a) * (longint'($signed(b_nib[i])) + longint'(c_in[i]));
        check_value(sgn_a, exp, "RECODED");
    endtask

    task automatic check_codes(input bit sgn_a);
        longint exp;
        is_signed_a = sgn_a;
        exp = 0;
        for (int i = 0; i < LANES; i++)
            exp += a_val(i, sgn_a) * (dec_nr4sd(b_nr4sd[i]) + 4 * dec_booth(b_booth[i]));
        check_value(sgn_a, exp, "CODES");
    endtask

    task automatic check_recoded_all;
        check_recoded(1'b0);
        check_recoded(1'b1);
    endtask

    task automatic check_codes_all;
        check_codes(1'b0);
        check_codes(1'b1);
    endtask

    task automatic rand_a;
        int pa;
        for (int i = 0; i < LANES; i++) begin
            pa = $urandom % 5;
            a_v[i] = (pa == 0) ? A_MIN_NEG : (pa == 1) ? A_MAX_POS : WIDTH_A'($urandom);
        end
    endtask

    task automatic rand_nib;
        int pb;
        for (int i = 0; i < LANES; i++) begin
            pb = $urandom % 5;
            b_nib[i] = (pb == 0) ? B_MIN_NEG : (pb == 1) ? B_MAX_POS : WIDTH_B'($urandom);
            c_in[i]  = 1'($urandom);
        end
    endtask

    task automatic rand_codes;
        int pc;
        for (int i = 0; i < LANES; i++) begin
            pc = $urandom % 6;
            case (pc)
                0: begin b_nr4sd[i] = 2'b10; b_booth[i] = 3'b011; end
                1: begin b_nr4sd[i] = 2'b11; b_booth[i] = 3'b100; end
                2: begin b_nr4sd[i] = 2'b10; b_booth[i] = 3'b100; end
                default: begin b_nr4sd[i] = CODE_WIDTH'($urandom); b_booth[i] = SEL_WIDTH'($urandom); end
            endcase
        end
    endtask

    task automatic set_a(input logic [WIDTH_A-1:0] av);
        for (int i = 0; i < LANES; i++) a_v[i] = av;
    endtask

    task automatic set_nib(input logic [WIDTH_B-1:0] bv, input bit cin);
        for (int i = 0; i < LANES; i++) begin
            b_nib[i] = bv;
            c_in[i]  = cin;
        end
    endtask

    task automatic set_codes(input logic [CODE_WIDTH-1:0] cv, input logic [SEL_WIDTH-1:0] wv);
        for (int i = 0; i < LANES; i++) begin
            b_nr4sd[i] = cv;
            b_booth[i] = wv;
        end
    endtask

    initial begin
        $display("\nStarting dp_8_nr4sd_bfp verification (LANES=%0d WIDTH_A=%0d WIDTH_B=%0d codes=%0d+%0d bits OUT_WIDTH=%0d)...\n",
                 LANES, WIDTH_A, WIDTH_B, CODE_WIDTH, SEL_WIDTH, OUT_WIDTH);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_dp_8_nr4sd_bfp.dp_8_nr4sd_bfp_i);
`endif

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_a;
            rand_nib;
            check_recoded_all;
        end
        for (int cin = 0; cin < 2; cin++) begin
            set_a(A_ZERO);     set_nib(B_ZERO,     1'(cin)); check_recoded_all;
            set_a(A_MAX_POS);  set_nib(B_MAX_POS,  1'(cin)); check_recoded_all;
            set_a(A_MIN_NEG);  set_nib(B_MIN_NEG,  1'(cin)); check_recoded_all;
            set_a(A_MAX_POS);  set_nib(B_MIN_NEG,  1'(cin)); check_recoded_all;
            set_a(A_MIN_NEG);  set_nib(B_MAX_POS,  1'(cin)); check_recoded_all;
            set_a(A_ALL_ONES); set_nib(B_ALL_ONES, 1'(cin)); check_recoded_all;
            set_a(A_ALL_ONES); set_nib(B_MIN_NEG,  1'(cin)); check_recoded_all;
            set_a(A_MIN_NEG);  set_nib(B_ALL_ONES, 1'(cin)); check_recoded_all;
            set_a(A_MAX_POS);  set_nib(B_ZERO,     1'(cin)); check_recoded_all;
            set_a(A_MIN_NEG);  set_nib(B_ZERO,     1'(cin)); check_recoded_all;
            set_a(A_ALL_ONES); set_nib(B_ZERO,     1'(cin)); check_recoded_all;
            set_a(A_ZERO);     set_nib(B_MAX_POS,  1'(cin)); check_recoded_all;
            set_a(A_ZERO);     set_nib(B_MIN_NEG,  1'(cin)); check_recoded_all;
            set_a(A_ZERO);     set_nib(B_ALL_ONES, 1'(cin)); check_recoded_all;
        end

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_a;
            rand_codes;
            check_codes_all;
        end
        set_a(A_MAX_POS);  set_codes(2'b10, 3'b011); check_codes_all;
        set_a(A_MIN_NEG);  set_codes(2'b10, 3'b011); check_codes_all;
        set_a(A_MAX_POS);  set_codes(2'b11, 3'b100); check_codes_all;
        set_a(A_MIN_NEG);  set_codes(2'b11, 3'b100); check_codes_all;
        set_a(A_ALL_ONES); set_codes(2'b10, 3'b011); check_codes_all;
        set_a(A_ALL_ONES); set_codes(2'b11, 3'b100); check_codes_all;
        set_a(A_MIN_NEG);  set_codes(2'b00, 3'b000); check_codes_all;
        set_a(A_ALL_ONES); set_codes(2'b00, 3'b000); check_codes_all;

`ifdef VCD
        $dumpoff;
`endif
        $display("\ndp_8_nr4sd_bfp: all %0d recoded + %0d code-space random + corner tests PASSED!\n",
                 NUM_RAND, NUM_RAND);
        $finish;
    end

endmodule
