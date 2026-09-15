// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for the BFP exponent dispatchers
//   disp_array_exp_a_bfp and disp_array_exp_b_bfp. For each of the 11
//   operating modes it drives the mode's dispatch control vector (block
//   selects + B-gate ops, the same tables as tb_disp_array), pushes NUM_RAND
//   random exponent words plus a directed ramp vector through the input
//   registers, and checks every DP8 exponent output against a golden router
//   model (block-select, high/low B split, per-half ZERO-only gate: the ZERO
//   code masks the half, NEG / NEG_CARRY pass the exponent unchanged - modes
//   10/11 are the directed check that a mantissa negation never touches its
//   scale, modes 5/6 the check that an idle half is masked while its sibling
//   survives). A final sweep drives fully random selects and gate ops to
//   cover control combinations no mode produces. Reports a fatal error on
//   any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random exponent vectors per mode (and per sweep)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_disp_array_exp_bfp #(
    parameter int NUM_RAND = 500
);

    localparam real CLK_PERIOD = `CLK_PERIOD_NS;
    localparam real CLK_HALF   = CLK_PERIOD / 2.0;
    localparam real T_SETTLE   = CLK_PERIOD / 10.0;

    localparam int NUM_BLK    = 4;
    localparam int EXP_WIDTH  = 6;
    localparam int CHK_WIDTH  = 2 * EXP_WIDTH;
    localparam int A_WIDTH    = NUM_BLK * EXP_WIDTH;
    localparam int B_WIDTH    = NUM_BLK * CHK_WIDTH;
    localparam int NUM_PAIR   = 8;
    localparam int NUM_DP8    = 16;
    localparam int SEL_WIDTH  = 2;
    localparam int OP_WIDTH   = 2;
    localparam int NUM_MODE   = 11;

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
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd1, 2'd1, 2'd1, 2'd1, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd2, 2'd0, 2'd0},
        '{2'd0, 2'd2, 2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0}
    };

    localparam logic [1:0] CTR_H [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd3, 2'd0, 2'd0, 2'd0, 2'd3, 2'd0, 2'd0},
        '{2'd0, 2'd3, 2'd0, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0}
    };

    logic                   clk_i;
    logic                   rst_ni;
    logic [    A_WIDTH-1:0] pe_exp_a;
    logic [    B_WIDTH-1:0] pe_exp_b;
    logic [  SEL_WIDTH-1:0] sel_a     [0:NUM_PAIR-1];
    logic [  SEL_WIDTH-1:0] sel_b     [0:NUM_PAIR-1];
    logic [   OP_WIDTH-1:0] ctr_l     [0:NUM_PAIR-1];
    logic [   OP_WIDTH-1:0] ctr_h     [0:NUM_PAIR-1];
    logic [  EXP_WIDTH-1:0] exp_a_dp8 [ 0:NUM_DP8-1];
    logic [  EXP_WIDTH-1:0] exp_b_dp8 [ 0:NUM_DP8-1];

    disp_array_exp_a_bfp disp_array_exp_a_bfp_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .pe_exp_a_i (pe_exp_a),
        .sel_a_i    (sel_a),
        .ctr_l_i    (ctr_l),
        .ctr_h_i    (ctr_h),
        .exp_a_dp8_o(exp_a_dp8)
    );

    disp_array_exp_b_bfp disp_array_exp_b_bfp_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .pe_exp_b_i (pe_exp_b),
        .sel_b_i    (sel_b),
        .ctr_l_i    (ctr_l),
        .ctr_h_i    (ctr_h),
        .exp_b_dp8_o(exp_b_dp8)
    );

    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    function automatic logic [EXP_WIDTH-1:0] gate6(input logic [EXP_WIDTH-1:0] x, input logic [OP_WIDTH-1:0] op);
        return (op == 2'd1) ? '0 : x;
    endfunction

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_A[mi][p];
            sel_b[p] = SEL_B[mi][p];
            ctr_l[p] = CTR_L[mi][p];
            ctr_h[p] = CTR_H[mi][p];
        end
    endtask

    task automatic rand_controls();
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_WIDTH'($urandom);
            sel_b[p] = SEL_WIDTH'($urandom);
            ctr_l[p] = OP_WIDTH'($urandom);
            ctr_h[p] = OP_WIDTH'($urandom);
        end
    endtask

    task automatic check(input string tag);
        logic [EXP_WIDTH-1:0] a_sel;
        logic [CHK_WIDTH-1:0] b_sel;
        logic [EXP_WIDTH-1:0] a_exp [0:NUM_DP8-1];
        logic [EXP_WIDTH-1:0] b_exp [0:NUM_DP8-1];
        for (int p = 0; p < NUM_PAIR; p++) begin
            a_sel = pe_exp_a[int'(sel_a[p])*EXP_WIDTH +: EXP_WIDTH];
            b_sel = pe_exp_b[int'(sel_b[p])*CHK_WIDTH +: CHK_WIDTH];
            a_exp[2*p+0] = gate6(a_sel, ctr_h[p]);
            a_exp[2*p+1] = gate6(a_sel, ctr_l[p]);
            b_exp[2*p+0] = gate6(b_sel[CHK_WIDTH-1:EXP_WIDTH], ctr_h[p]);
            b_exp[2*p+1] = gate6(b_sel[EXP_WIDTH-1:0],         ctr_l[p]);
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            if (exp_a_dp8[i] !== a_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("A MISMATCH %s dp8=%0d exp=%h got=%h", tag, i, a_exp[i], exp_a_dp8[i]);
                $fatal;
            end
            if (exp_b_dp8[i] !== b_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("B MISMATCH %s dp8=%0d exp=%h got=%h", tag, i, b_exp[i], exp_b_dp8[i]);
                $fatal;
            end
        end
    endtask

    task automatic rand_vec;
        pe_exp_a = A_WIDTH'({$urandom, $urandom});
        pe_exp_b = B_WIDTH'({$urandom, $urandom});
    endtask

    task automatic ramp_vec;
        for (int e = 0; e < NUM_BLK;     e++) pe_exp_a[e*EXP_WIDTH +: EXP_WIDTH] = EXP_WIDTH'(e + 1);
        for (int e = 0; e < 2 * NUM_BLK; e++) pe_exp_b[e*EXP_WIDTH +: EXP_WIDTH] = EXP_WIDTH'(e + 8);
    endtask

    initial begin
        string tag;
        $display("\nStarting disp_array_exp_bfp verification (%0d modes x (%0d random + ramp) + %0d random-ctrl)...\n",
                 NUM_MODE, NUM_RAND, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_disp_array_exp_bfp);
`endif

        rst_ni   = 1'b0;
        pe_exp_a = '0;
        pe_exp_b = '0;
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = '0; sel_b[p] = '0; ctr_l[p] = '0; ctr_h[p] = '0;
        end
        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;

        for (int mi = 0; mi < NUM_MODE; mi++) begin
            set_controls(mi);
            tag = $sformatf("mode=%0d", MODE_NUM[mi]);
            for (int t = 0; t < NUM_RAND; t++) begin
                rand_vec;
                @(posedge clk_i);
                #(T_SETTLE);
                check(tag);
            end
            ramp_vec;
            @(posedge clk_i);
            #(T_SETTLE);
            check(tag);
            $display("  mode %0d: PASS", MODE_NUM[mi]);
        end

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_controls();
            rand_vec;
            @(posedge clk_i);
            #(T_SETTLE);
            check("random-ctrl");
        end
        $display("  random-ctrl sweep: PASS");

`ifdef VCD
        $dumpoff;
`endif
        $display("\ndisp_array_exp_bfp: all %0d modes x (%0d random + ramp) + %0d random-ctrl tests PASSED!\n",
                 NUM_MODE, NUM_RAND, NUM_RAND);
        $finish;
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
