// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for the bit-plane B dispatch pair,
//   disp_array_a_bpl_b_bfp and disp_array_b. For each of the 11 operating modes
//   it drives the mode's real dispatch control vector - block selects, B-gate ops
//   and per-DP8 A signedness taken verbatim from ctrl's lookup tables - pushes
//   NUM_RAND random 256-bit operands plus a directed ramp vector through the
//   input registers, and checks all three outputs against a golden model.
//
//   The A side is where the work is: the golden reproduces the block select, the
//   duplication onto both DP8s of a pair, the signedness-aware widening to 9
//   bits, and the four pairwise sums at 10 bits. The B side is the plain
//   disp_array_b route - block select, high/low split and the per-int4 gate
//   including the two's-complement carry that ripples from the low half into the
//   high half - checked as raw gated nibbles.
//
//   The negate modes are driven with ctrl's carry-chained control (GATE_NEG on
//   the low half, GATE_NEG_CARRY on the high half), so the cross-half carry is
//   exercised. Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random operand vectors per mode
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_disp_array_bpl_b_bfp #(
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
    localparam int A_ELEM_WIDTH  = 8;
    localparam int NUM_A_ELEM    = 8;
    localparam int A_OUT_WIDTH   = 9;
    localparam int A_SUM_WIDTH   = 10;
    localparam int NUM_A_SUM     = 4;
    localparam int A_DP8_WIDTH   = NUM_A_ELEM * A_OUT_WIDTH;
    localparam int A_SDP8_WIDTH  = NUM_A_SUM * A_SUM_WIDTH;
    localparam int B_ELEM_WIDTH  = 4;
    localparam int NUM_B_ELEM    = 8;
    localparam int B_DP8_WIDTH   = 32;
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

    localparam logic IS_SIGNED_A [0:NUM_MODE-1][0:NUM_DP8-1] = '{
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0},
        '{1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0},
        '{1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0}
    };

    logic                         clk_i;
    logic                         rst_ni;
    logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_a;
    logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b;
    logic [        SEL_WIDTH-1:0] sel_a       [0:NUM_PAIR-1];
    logic [        SEL_WIDTH-1:0] sel_b       [0:NUM_PAIR-1];
    logic [         OP_WIDTH-1:0] ctr_l       [0:NUM_PAIR-1];
    logic [         OP_WIDTH-1:0] ctr_h       [0:NUM_PAIR-1];
    logic                         is_signed_a [ 0:NUM_DP8-1];
    logic [      A_DP8_WIDTH-1:0] a_dp8       [ 0:NUM_DP8-1];
    logic [     A_SDP8_WIDTH-1:0] a_sum_dp8   [ 0:NUM_DP8-1];
    logic [      B_DP8_WIDTH-1:0] b_dp8       [ 0:NUM_DP8-1];

    disp_array_a_bpl_b_bfp disp_array_a_bpl_b_bfp_i (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .pe_in_a_i    (pe_in_a),
        .sel_a_i      (sel_a),
        .is_signed_a_i(is_signed_a),
        .a_dp8_o      (a_dp8),
        .a_sum_dp8_o  (a_sum_dp8)
    );

    disp_array_b disp_array_b_i (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .pe_in_b_i(pe_in_b),
        .sel_b_i  (sel_b),
        .ctr_l_i  (ctr_l),
        .ctr_h_i  (ctr_h),
        .b_dp8_o  (b_dp8)
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

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_A[mi][p];
            sel_b[p] = SEL_B[mi][p];
            ctr_l[p] = CTR_L[mi][p];
            ctr_h[p] = CTR_H[mi][p];
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = IS_SIGNED_A[mi][i];
        end
    endtask

    task automatic check(input int mi);
        logic [    BLK_WIDTH-1:0] a_sel;
        logic [    BLK_WIDTH-1:0] b_sel;
        logic [ A_ELEM_WIDTH-1:0] a_elem;
        logic [  A_OUT_WIDTH-1:0] a_res  [0:NUM_A_ELEM-1];
        logic [ B_ELEM_WIDTH-1:0] lo_g   [0:NUM_B_ELEM-1];
        logic [ B_ELEM_WIDTH-1:0] hi_g   [0:NUM_B_ELEM-1];
        logic [ B_ELEM_WIDTH-1:0] nib;
        logic [   B_ELEM_WIDTH:0] gres;
        logic                     lo_c   [0:NUM_B_ELEM-1];
        logic [  A_DP8_WIDTH-1:0] a_exp  [  0:NUM_DP8-1];
        logic [ A_SDP8_WIDTH-1:0] s_exp  [  0:NUM_DP8-1];
        logic [  B_DP8_WIDTH-1:0] b_exp  [  0:NUM_DP8-1];
        int oa, ob;
        for (int p = 0; p < NUM_PAIR; p++) begin
            oa    = int'(SEL_A[mi][p]) * BLK_WIDTH;
            ob    = int'(SEL_B[mi][p]) * BLK_WIDTH;
            a_sel = pe_in_a[oa +: BLK_WIDTH];
            b_sel = pe_in_b[ob +: BLK_WIDTH];

            for (int e = 0; e < NUM_A_ELEM; e++) begin
                a_elem   = a_sel[e*A_ELEM_WIDTH +: A_ELEM_WIDTH];
                a_res[e] = {IS_SIGNED_A[mi][2*p] & a_elem[A_ELEM_WIDTH-1], a_elem};
                a_exp[2*p+0][e*A_OUT_WIDTH +: A_OUT_WIDTH] = a_res[e];
                a_exp[2*p+1][e*A_OUT_WIDTH +: A_OUT_WIDTH] = a_res[e];
            end
            for (int s = 0; s < NUM_A_SUM; s++) begin
                s_exp[2*p+0][s*A_SUM_WIDTH +: A_SUM_WIDTH] =
                    A_SUM_WIDTH'(A_SUM_WIDTH'($signed(a_res[2*s+0])) +
                                 A_SUM_WIDTH'($signed(a_res[2*s+1])));
                s_exp[2*p+1][s*A_SUM_WIDTH +: A_SUM_WIDTH] =
                    s_exp[2*p+0][s*A_SUM_WIDTH +: A_SUM_WIDTH];
            end

            for (int e = 0; e < NUM_B_ELEM; e++) begin
                nib     = b_sel[e*B_ELEM_WIDTH +: B_ELEM_WIDTH];
                gres    = gate_nib(nib, CTR_L[mi][p], 1'b0);
                lo_g[e] = gres[B_ELEM_WIDTH-1:0];
                lo_c[e] = gres[B_ELEM_WIDTH];
                nib     = b_sel[NUM_B_ELEM*B_ELEM_WIDTH + e*B_ELEM_WIDTH +: B_ELEM_WIDTH];
                gres    = gate_nib(nib, CTR_H[mi][p], lo_c[e]);
                hi_g[e] = gres[B_ELEM_WIDTH-1:0];
            end
            for (int e = 0; e < NUM_B_ELEM; e++) begin
                b_exp[2*p+0][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = hi_g[e];
                b_exp[2*p+1][e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = lo_g[e];
            end
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            if (a_dp8[i] !== a_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("A MISMATCH mode=%0d dp8=%0d exp=%h got=%h", MODE_NUM[mi], i, a_exp[i], a_dp8[i]);
                $fatal;
            end
            if (a_sum_dp8[i] !== s_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("A SUM MISMATCH mode=%0d dp8=%0d exp=%h got=%h", MODE_NUM[mi], i, s_exp[i], a_sum_dp8[i]);
                $fatal;
            end
            if (b_dp8[i] !== b_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("B MISMATCH mode=%0d dp8=%0d exp=%h got=%h", MODE_NUM[mi], i, b_exp[i], b_dp8[i]);
                $fatal;
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
        $display("\nStarting disp_array_bpl_b_bfp verification (%0d modes x (%0d random + ramp))...\n",
                 NUM_MODE, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_disp_array_bpl_b_bfp);
`endif

        rst_ni  = 1'b0;
        pe_in_a = '0;
        pe_in_b = '0;
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = '0; sel_b[p] = '0; ctr_l[p] = '0; ctr_h[p] = '0;
        end
        for (int i = 0; i < NUM_DP8; i++) is_signed_a[i] = 1'b0;
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
        $display("\ndisp_array_bpl_b_bfp: all %0d modes x (%0d random + ramp) tests PASSED!\n",
                 NUM_MODE, NUM_RAND);
        $finish;
    end

endmodule
