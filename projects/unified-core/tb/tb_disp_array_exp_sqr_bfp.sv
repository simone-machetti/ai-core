// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for the square-variant BFP exponent dispatchers
//   disp_array_exp_a_sqr_bfp and disp_array_exp_b_sqr_bfp. For each of the 11
//   operating modes it drives the mode's dispatch control vectors (block
//   selects + per-DP8 idle zero, the same tables as tb_disp_array_sqr), pushes
//   NUM_RAND random exponent words plus a directed ramp vector through the
//   input registers, and checks every DP8 exponent output against a golden
//   router model (block-select, high/low B split, per-DP8 zero_i mask). Modes
//   5/6 are the directed check that a partly-idle pair masks the right half
//   while its sibling survives (mode 5 idles alternating DP8s, mode 6 the whole
//   second half). A final sweep drives fully random selects and per-DP8 zero
//   bits to cover control combinations no mode produces. Reports a fatal error
//   on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random exponent vectors per mode (and per sweep)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_disp_array_exp_sqr_bfp #(
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

    localparam logic ZERO_I_LUT [0:NUM_MODE-1][0:NUM_DP8-1] = '{
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0},
        '{default: 1'b0}
    };

    logic                   clk_i;
    logic                   rst_ni;
    logic [    A_WIDTH-1:0] pe_exp_a;
    logic [    B_WIDTH-1:0] pe_exp_b;
    logic [  SEL_WIDTH-1:0] sel_a     [0:NUM_PAIR-1];
    logic [  SEL_WIDTH-1:0] sel_b     [0:NUM_PAIR-1];
    logic                   zero_dp8  [0:NUM_DP8-1];
    logic [  EXP_WIDTH-1:0] exp_a_dp8 [ 0:NUM_DP8-1];
    logic [  EXP_WIDTH-1:0] exp_b_dp8 [ 0:NUM_DP8-1];

    disp_array_exp_a_sqr_bfp disp_array_exp_a_sqr_bfp_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .pe_exp_a_i (pe_exp_a),
        .sel_a_i    (sel_a),
        .zero_i     (zero_dp8),
        .exp_a_dp8_o(exp_a_dp8)
    );

    disp_array_exp_b_sqr_bfp disp_array_exp_b_sqr_bfp_i (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .pe_exp_b_i (pe_exp_b),
        .sel_b_i    (sel_b),
        .zero_i     (zero_dp8),
        .exp_b_dp8_o(exp_b_dp8)
    );

    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    function automatic logic [EXP_WIDTH-1:0] gate6(input logic [EXP_WIDTH-1:0] x, input logic z);
        return z ? '0 : x;
    endfunction

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_A[mi][p];
            sel_b[p] = SEL_B[mi][p];
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            zero_dp8[i] = ZERO_I_LUT[mi][i];
        end
    endtask

    task automatic rand_controls();
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_WIDTH'($urandom);
            sel_b[p] = SEL_WIDTH'($urandom);
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            zero_dp8[i] = 1'($urandom);
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
            a_exp[2*p+0] = gate6(a_sel, zero_dp8[2*p+0]);
            a_exp[2*p+1] = gate6(a_sel, zero_dp8[2*p+1]);
            b_exp[2*p+0] = gate6(b_sel[CHK_WIDTH-1:EXP_WIDTH], zero_dp8[2*p+0]);
            b_exp[2*p+1] = gate6(b_sel[EXP_WIDTH-1:0],         zero_dp8[2*p+1]);
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
        $display("\nStarting disp_array_exp_sqr_bfp verification (%0d modes x (%0d random + ramp) + %0d random-ctrl)...\n",
                 NUM_MODE, NUM_RAND, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_disp_array_exp_sqr_bfp);
`endif

        rst_ni   = 1'b0;
        pe_exp_a = '0;
        pe_exp_b = '0;
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = '0; sel_b[p] = '0;
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            zero_dp8[i] = 1'b0;
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
        $display("\ndisp_array_exp_sqr_bfp: all %0d modes x (%0d random + ramp) + %0d random-ctrl tests PASSED!\n",
                 NUM_MODE, NUM_RAND, NUM_RAND);
        $finish;
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
