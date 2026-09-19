// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Self-checking testbench for the NR4SD dispatch pair, disp_array_a and
//   disp_array_b_nr4sd_bfp. For each of the 11 operating modes it drives the
//   mode's real dispatch control vector - block selects, B-gate ops and per-DP8 B
//   signedness taken verbatim from ctrl's lookup tables - pushes NUM_RAND random
//   256-bit operands plus a directed ramp vector through the input registers, and
//   checks both outputs against a golden model.
//
//   The B side is where the work is: the golden reproduces the whole chain -
//   block select, high/low split, the per-int4 gate INCLUDING the two's-complement
//   carry that ripples from the low half into the high half, then the cross-nibble
//   LINK of the 2-PP scheme (the carry-in of DP8 i is the MSB of the gated nibble
//   of DP8 i+1, enabled when that DP8 holds a lower nibble, never across a quad
//   boundary), and finally the hybrid recode of the gated nibble with that
//   carry-in. The recode must be of the GATED value, so a golden that recoded
//   before gating would pass on the pass modes and fail on the negate and idle
//   ones; and the link must be taken after the gate too. The A side is the plain
//   disp_array_a block route, duplicated onto both DP8s of a pair.
//
//   The software recoder is written from the ARITHMETIC definition of the hybrid
//   (NR4SD+ low pair: s = raw + carry, emit s-4 and a carry when s >= 3; Booth top
//   pair: the pair read as signed plus that carry) and the comparison is by DIGIT
//   VALUE: the DUT's 2-bit code and 3-bit window are decoded with their cells'
//   tables, so the bench accepts any window that means the right Booth digit
//   rather than the wiring nr4sd_r4 happens to emit.
//
//   The negate modes are driven with ctrl's carry-chained control (GATE_NEG on
//   the low half, GATE_NEG_CARRY on the high half), so the cross-half carry is
//   exercised - and, because the recoders sit downstream of it, so is the recode
//   of a negated operand. The int16 modes (8, 9, 12) exercise the cross-pair
//   link 4q+1 <- 4q+2. Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random operand vectors per mode
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_disp_array_nr4sd_bfp #(
    parameter int NUM_RAND = 500
);

    localparam real CLK_PERIOD   = `CLK_PERIOD_NS;
    localparam real CLK_HALF     = CLK_PERIOD / 2.0;
    localparam real T_SETTLE     = CLK_PERIOD / 10.0;

    localparam int NUM_BLK       = 4;
    localparam int BLK_WIDTH     = 64;
    localparam int NUM_PAIR      = 8;
    localparam int NUM_DP8       = 16;
    localparam int SEL_WIDTH     = 2;
    localparam int OP_WIDTH      = 2;
    localparam int A_DP8_WIDTH   = 64;
    localparam int B_ELEM_WIDTH  = 4;
    localparam int NUM_B_ELEM    = 8;
    localparam int CODE_WIDTH    = 2;
    localparam int BSEL_WIDTH    = 3;
    localparam int B_NR4SD_WIDTH = NUM_B_ELEM * CODE_WIDTH;
    localparam int B_BOOTH_WIDTH = NUM_B_ELEM * BSEL_WIDTH;
    localparam int NUM_MODE      = 11;

    localparam int MODE_NUM [0:NUM_MODE-1] = '{1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12};

    localparam logic [1:0] SEL_A [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd0, 2'd1, 2'd1}
    };

    localparam logic [1:0] SEL_B [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd0, 2'd1, 2'd1},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},
        '{2'd0, 2'd1, 2'd1, 2'd0, 2'd2, 2'd3, 2'd3, 2'd2},
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd1, 2'd0, 2'd3, 2'd2},
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3}
    };

    localparam logic [1:0] CTR_L [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd1, 2'd1, 2'd1, 2'd1, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd2, 2'd0, 2'd0},
        '{2'd0, 2'd2, 2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd0},
        '{default: 2'd0}
    };

    localparam logic [1:0] CTR_H [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{default: 2'd0},
        '{default: 2'd0},
        '{default: 2'd0},
        '{2'd0, 2'd3, 2'd0, 2'd0, 2'd0, 2'd3, 2'd0, 2'd0},
        '{2'd0, 2'd3, 2'd0, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},
        '{default: 2'd0}
    };

    localparam logic IS_SIGNED_B [0:NUM_MODE-1][0:NUM_DP8-1] = '{
        '{default: 1'b1},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0},
        '{1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0},
        '{1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0}
    };

    logic                         clk_i;
    logic                         rst_ni;
    logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_a;
    logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b;
    logic [        SEL_WIDTH-1:0] sel_a       [0:NUM_PAIR-1];
    logic [        SEL_WIDTH-1:0] sel_b       [0:NUM_PAIR-1];
    logic [         OP_WIDTH-1:0] ctr_l       [0:NUM_PAIR-1];
    logic [         OP_WIDTH-1:0] ctr_h       [0:NUM_PAIR-1];
    logic                         is_signed_b [ 0:NUM_DP8-1];
    logic [      A_DP8_WIDTH-1:0] a_dp8       [ 0:NUM_DP8-1];
    logic [    B_NR4SD_WIDTH-1:0] b_nr4sd_dp8 [ 0:NUM_DP8-1];
    logic [    B_BOOTH_WIDTH-1:0] b_booth_dp8 [ 0:NUM_DP8-1];

    disp_array_a disp_array_a_i (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .pe_in_a_i(pe_in_a),
        .sel_a_i  (sel_a),
        .a_dp8_o  (a_dp8)
    );

    disp_array_b_nr4sd_bfp disp_array_b_nr4sd_bfp_i (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .pe_in_b_i    (pe_in_b),
        .sel_b_i      (sel_b),
        .ctr_l_i      (ctr_l),
        .ctr_h_i      (ctr_h),
        .is_signed_b_i(is_signed_b),
        .b_nr4sd_dp8_o(b_nr4sd_dp8),
        .b_booth_dp8_o(b_booth_dp8)
    );

    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    function automatic logic [B_ELEM_WIDTH:0] gate_nib(input logic [B_ELEM_WIDTH-1:0] x,
                                                       input logic [OP_WIDTH-1:0]     op,
                                                       input logic                    cin);
        case (op)
            2'd1:    return {1'b0, {B_ELEM_WIDTH{1'b0}}};
            2'd2:    return {1'b0, ~x} + 1'b1;
            2'd3:    return {1'b0, ~x} + cin;
            default: return {1'b0, x};
        endcase
    endfunction

    function automatic int dec_nr4sd(input logic [CODE_WIDTH-1:0] code);
        case (code)
            2'b00:   dec_nr4sd =  0;
            2'b01:   dec_nr4sd =  1;
            2'b10:   dec_nr4sd =  2;
            default: dec_nr4sd = -1;
        endcase
    endfunction

    function automatic int dec_booth(input logic [BSEL_WIDTH-1:0] w);
        dec_booth = -2 * int'(w[2]) + int'(w[1]) + int'(w[0]);
    endfunction

    task automatic recode(input logic [B_ELEM_WIDTH-1:0] b, input logic cin,
                          output int d0, output int d1);
        int s;
        int c1;
        s = int'({b[1], b[0]}) + int'(cin);
        if (s >= 3) begin
            d0 = s - 4;
            c1 = 1;
        end else begin
            d0 = s;
            c1 = 0;
        end
        d1 = -2 * int'(b[3]) + int'(b[2]) + c1;
    endtask

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_A[mi][p];
            sel_b[p] = SEL_B[mi][p];
            ctr_l[p] = CTR_L[mi][p];
            ctr_h[p] = CTR_H[mi][p];
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_b[i] = IS_SIGNED_B[mi][i];
        end
    endtask

    task automatic check(input int mi);
        logic [   BLK_WIDTH-1:0] a_sel;
        logic [   BLK_WIDTH-1:0] b_sel;
        logic [B_ELEM_WIDTH-1:0] nib;
        logic [  B_ELEM_WIDTH:0] gres;
        logic                    lo_c   [0:NUM_B_ELEM-1];
        logic [B_ELEM_WIDTH-1:0] gated  [0:NUM_DP8-1][0:NUM_B_ELEM-1];
        logic                    cin    [0:NUM_DP8-1][0:NUM_B_ELEM-1];
        logic [ A_DP8_WIDTH-1:0] a_exp  [0:NUM_DP8-1];
        int d0_exp, d1_exp, d0_got, d1_got;
        int oa, ob;
        // 1. route, split, gate - the same value the DP8 multiplies
        for (int p = 0; p < NUM_PAIR; p++) begin
            oa    = int'(SEL_A[mi][p]) * BLK_WIDTH;
            ob    = int'(SEL_B[mi][p]) * BLK_WIDTH;
            a_sel = pe_in_a[oa +: BLK_WIDTH];
            b_sel = pe_in_b[ob +: BLK_WIDTH];
            a_exp[2*p+0] = a_sel;
            a_exp[2*p+1] = a_sel;
            for (int e = 0; e < NUM_B_ELEM; e++) begin
                nib              = b_sel[e*B_ELEM_WIDTH +: B_ELEM_WIDTH];
                gres             = gate_nib(nib, CTR_L[mi][p], 1'b0);
                gated[2*p+1][e]  = gres[B_ELEM_WIDTH-1:0];
                lo_c[e]          = gres[B_ELEM_WIDTH];
                nib              = b_sel[NUM_B_ELEM*B_ELEM_WIDTH + e*B_ELEM_WIDTH +: B_ELEM_WIDTH];
                gres             = gate_nib(nib, CTR_H[mi][p], lo_c[e]);
                gated[2*p+0][e]  = gres[B_ELEM_WIDTH-1:0];
            end
        end
        // 2. cross-nibble link: DP8 i takes the MSB of the gated nibble of DP8 i+1
        //    when that DP8 holds a lower nibble; never across a quad boundary
        for (int i = 0; i < NUM_DP8; i++)
            for (int e = 0; e < NUM_B_ELEM; e++)
                if (i % 4 == 3) cin[i][e] = 1'b0;
                else            cin[i][e] = !IS_SIGNED_B[mi][i+1] && gated[i+1][e][B_ELEM_WIDTH-1];
        // 3. recode and compare by digit value
        for (int i = 0; i < NUM_DP8; i++) begin
            if (a_dp8[i] !== a_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("A MISMATCH mode=%0d dp8=%0d exp=%h got=%h", MODE_NUM[mi], i, a_exp[i], a_dp8[i]);
                $fatal;
            end
            for (int e = 0; e < NUM_B_ELEM; e++) begin
                recode(gated[i][e], cin[i][e], d0_exp, d1_exp);
                d0_got = dec_nr4sd(b_nr4sd_dp8[i][e*CODE_WIDTH +: CODE_WIDTH]);
                d1_got = dec_booth(b_booth_dp8[i][e*BSEL_WIDTH +: BSEL_WIDTH]);
                if (d0_got !== d0_exp || d1_got !== d1_exp) begin
`ifdef VCD
                    $dumpoff;
`endif
                    $error("B DIGIT MISMATCH mode=%0d dp8=%0d lane=%0d nib=%b cin=%0d exp=(%0d,%0d) got=(%0d,%0d)",
                           MODE_NUM[mi], i, e, gated[i][e], cin[i][e], d0_exp, d1_exp, d0_got, d1_got);
                    $fatal;
                end
            end
        end
    endtask

    task automatic rand_vec;
        for (int w = 0; w < NUM_BLK*BLK_WIDTH/32; w++) begin
            pe_in_a[w*32 +: 32] = $urandom;
            pe_in_b[w*32 +: 32] = $urandom;
        end
    endtask

    task automatic ramp_vec;
        for (int by = 0; by < NUM_BLK*BLK_WIDTH/8; by++) pe_in_a[by*8 +: 8] = by[7:0];
        for (int ni = 0; ni < NUM_BLK*BLK_WIDTH/4; ni++) pe_in_b[ni*4 +: 4] = ni[3:0];
    endtask

    initial begin
        $display("\nStarting disp_array_nr4sd_bfp verification (%0d modes x (%0d random + ramp))...\n",
                 NUM_MODE, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_disp_array_nr4sd_bfp);
`endif

        rst_ni  = 1'b0;
        pe_in_a = '0;
        pe_in_b = '0;
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = '0; sel_b[p] = '0; ctr_l[p] = '0; ctr_h[p] = '0;
        end
        for (int i = 0; i < NUM_DP8; i++) is_signed_b[i] = 1'b0;
        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;

        for (int mi = 0; mi < NUM_MODE; mi++) begin
            set_controls(mi);
            for (int t = 0; t < NUM_RAND; t++) begin
                rand_vec;
                @(posedge clk_i);
                #(T_SETTLE);
                check(mi);
            end
            ramp_vec;
            @(posedge clk_i);
            #(T_SETTLE);
            check(mi);
            $display("  mode %0d: PASS", MODE_NUM[mi]);
        end

`ifdef VCD
        $dumpoff;
`endif
        $display("\ndisp_array_nr4sd_bfp: all %0d modes x (%0d random + ramp) tests PASSED!\n",
                 NUM_MODE, NUM_RAND);
        $finish;
    end

endmodule
