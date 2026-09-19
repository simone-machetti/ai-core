// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Self-checking testbench for nr4sd_r4, the hybrid NR4SD+/Booth recoder. The
//   input space is tiny - IN_WIDTH_B nibble bits plus the carry-in - so the bench
//   is EXHAUSTIVE: every one of the 2^(IN_WIDTH_B+1) (b, c_in) vectors is driven,
//   which proves the recoding total instead of sampling it.
//
//   Three properties are checked on every vector:
//
//     reconstruction - sum_j(digit_j * 4^j) == signed(b) + c_in, the defining
//                      property of the recoding: the nibble is always read as
//                      SIGNED and the carry-in adds one. The low digits are
//                      decoded from the 2-bit NR4SD+ code {00:0, 01:+1, 10:+2,
//                      11:-1}; the top digit is decoded from the 3-bit Booth
//                      window by Booth's own rule, -2*w[2] + w[1] + w[0], so the
//                      bench accepts ANY window that means the right digit rather
//                      than the one wiring the RTL happens to emit.
//     digit range    - every NR4SD+ digit lies in {-1,0,+1,+2}, the Booth digit in
//                      {-2,...,+2}.
//     zero code      - b == 0 with c_in == 0 recodes to the all-zero bus, the
//                      property pe_nr4sd_bfp's AND-mask relies on.
//
//   Plus one whole-sweep property per carry-in:
//
//     distinct encodings - the 2^IN_WIDTH_B encodings are pairwise DISTINCT. The
//                      value signed(b) + c_in is injective in b, so a collision
//                      would mean two nibbles recoded to the same digits.
//
//   Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   IN_WIDTH_B - bit width of the nibble b (forwarded to the DUT)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_nr4sd_r4 #(
    parameter int IN_WIDTH_B = 4
);

    localparam int NUM_PAIR    = IN_WIDTH_B / 2;
    localparam int CODE_WIDTH  = 2;
    localparam int SEL_WIDTH   = 3;
    localparam int NR4SD_WIDTH = (NUM_PAIR - 1) * CODE_WIDTH;
    localparam int ENC_WIDTH   = NR4SD_WIDTH + SEL_WIDTH;
    localparam int NUM_VEC     = 1 << IN_WIDTH_B;

    logic [ IN_WIDTH_B-1:0] b_v;
    logic                   c_in;
    logic [NR4SD_WIDTH-1:0] b_nr4sd;
    logic [  SEL_WIDTH-1:0] b_booth;

    logic [  ENC_WIDTH-1:0] seen [0:NUM_VEC-1];

    nr4sd_r4 #(
        .IN_WIDTH_B(IN_WIDTH_B)
    ) nr4sd_r4_i (
        .b_i      (b_v),
        .c_in_i   (c_in),
        .b_nr4sd_o(b_nr4sd),
        .b_booth_o(b_booth)
    );

    function automatic longint nr4sd_digit(input logic [CODE_WIDTH-1:0] code);
        case (code)
            2'b00:   nr4sd_digit =  0;
            2'b01:   nr4sd_digit =  1;
            2'b10:   nr4sd_digit =  2;
            default: nr4sd_digit = -1;
        endcase
    endfunction

    function automatic longint booth_digit(input logic [SEL_WIDTH-1:0] w);
        booth_digit = -2 * longint'(w[2]) + longint'(w[1]) + longint'(w[0]);
    endfunction

    task automatic check(input bit cin);
        longint b_val;
        longint dig_sum;
        longint d;
        c_in = cin;
        #1;
        b_val   = longint'($signed(b_v)) + longint'(cin);
        dig_sum = 0;
        for (int j = 0; j < NUM_PAIR - 1; j++) begin
            d = nr4sd_digit(b_nr4sd[j*CODE_WIDTH +: CODE_WIDTH]);
            if (d < -1 || d > 2) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("NR4SD DIGIT OUT OF SET c_in=%0d b=%0d j=%0d d=%0d", cin, $signed(b_v), j, d);
                $fatal;
            end
            dig_sum += d * (longint'(1) << (2 * j));
        end
        d = booth_digit(b_booth);
        if (d < -2 || d > 2) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("BOOTH DIGIT OUT OF SET c_in=%0d b=%0d d=%0d", cin, $signed(b_v), d);
            $fatal;
        end
        dig_sum += d * (longint'(1) << (2 * (NUM_PAIR - 1)));
        if (dig_sum !== b_val) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("MISMATCH c_in=%0d b=%0d nr4sd=%b booth=%b dig_sum=%0d expected=%0d",
                   cin, $signed(b_v), b_nr4sd, b_booth, dig_sum, b_val);
            $fatal;
        end
        if (b_v == '0 && !cin && {b_booth, b_nr4sd} !== '0) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("ZERO CODE: b=0 c_in=0 recoded to nr4sd=%b booth=%b", b_nr4sd, b_booth);
            $fatal;
        end
    endtask

    task automatic sweep(input bit cin);
        for (int v = 0; v < NUM_VEC; v++) begin
            b_v = IN_WIDTH_B'(v);
            check(cin);
            seen[v] = {b_booth, b_nr4sd};
        end
        for (int v = 0; v < NUM_VEC; v++) begin
            for (int w = v + 1; w < NUM_VEC; w++) begin
                if (seen[v] === seen[w]) begin
`ifdef VCD
                    $dumpoff;
`endif
                    $error("DUPLICATE ENCODING c_in=%0d b=%0d and b=%0d share enc=%b",
                           cin, v, w, seen[v]);
                    $fatal;
                end
            end
        end
    endtask

    initial begin
        $display("\nStarting nr4sd_r4 verification (IN_WIDTH_B=%0d NUM_PAIR=%0d ENC_WIDTH=%0d)...\n",
                 IN_WIDTH_B, NUM_PAIR, ENC_WIDTH);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_nr4sd_r4.nr4sd_r4_i);
`endif

        sweep(1'b0);
        sweep(1'b1);

`ifdef VCD
        $dumpoff;
`endif
        $display("nr4sd_r4: all %0d exhaustive tests (2 carry-ins x %0d values) PASSED!\n",
                 2 * NUM_VEC, NUM_VEC);
        $finish;
    end

endmodule
