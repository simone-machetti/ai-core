// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for pe_array_alpha_sqr_bfp, driven through the real
//   square A dispatcher (disp_array_a_sqr). For each of the 11 modes it pushes
//   NUM_RAND corner-biased random 256-bit A operands, lets the dispatcher
//   center / idle-zero them, and checks every one of the 16 per-DP8 -alpha
//   carry-save outputs against an independent software golden that replicates
//   dp_8_alpha_sqr:
//       ALPHA_DP8 = 2^4 * sum_k arg(AH_k)^2 + sum_k arg(AL_k)^2 ,
//       arg(n) = signed(n) - 8*(~is_signed_b)     (gate_n_sqr)
//   The module emits -alpha via a one's-complement of the carry-save pair, so
//   each output pair resolves to -ALPHA_DP8 - 2 (the +2 folded downstream into
//   const_sqr_bfp). Idle DP8s (ctrl forces is_signed_b = 1, A dispatcher-zeroed)
//   give ALPHA_DP8 = 0 -> resolve = -2. Reports a fatal error on any mismatch.
//
// Parameters:
//   NUM_RAND - number of random operand vectors per mode
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_pe_array_alpha_sqr_bfp #(
    parameter int NUM_RAND = 500
);

    localparam real CLK_PERIOD = `CLK_PERIOD_NS;
    localparam real CLK_HALF   = CLK_PERIOD / 2.0;
    localparam real T_SETTLE   = CLK_PERIOD / 10.0;

    localparam int PE_WIDTH    = 256;
    localparam int NUM_PAIR    = 8;
    localparam int NUM_DP8     = 16;
    localparam int SEL_WIDTH   = 2;
    localparam int A_DP8_WIDTH = 64;
    localparam int A_ELEM      = 8;
    localparam int B_ELEM      = 4;
    localparam int LANES       = 8;
    localparam int DP8_WIDTH   = 18;
    localparam int NUM_MODE    = 11;

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

    localparam logic IS_SIGNED_A [0:NUM_MODE-1][0:NUM_DP8-1] = '{
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0},
        '{1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0},
        '{1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0},
        '{default: 1'b1},
        '{default: 1'b1},
        '{1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0}
    };

    localparam logic IS_SIGNED_B [0:NUM_MODE-1][0:NUM_DP8-1] = '{
        '{default: 1'b1},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{default: 1'b1},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0},
        '{1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0,1'b1,1'b0},
        '{1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0}
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
    logic [   PE_WIDTH-1:0] pe_in_a;
    logic [  SEL_WIDTH-1:0] sel_a       [0:NUM_PAIR-1];
    logic                   is_signed_a [ 0:NUM_DP8-1];
    logic                   is_signed_b [ 0:NUM_DP8-1];
    logic                   zero_dp8    [ 0:NUM_DP8-1];
    logic [A_DP8_WIDTH-1:0] a_dp8       [ 0:NUM_DP8-1];
    logic [  DP8_WIDTH-1:0] alpha_sum   [ 0:NUM_DP8-1];
    logic [  DP8_WIDTH-1:0] alpha_carry [ 0:NUM_DP8-1];

    disp_array_a_sqr disp_array_a_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .pe_in_a_i(pe_in_a),
        .sel_a_i(sel_a), .is_signed_a_i(is_signed_a), .zero_i(zero_dp8),
        .a_dp8_o(a_dp8)
    );

    pe_array_alpha_sqr_bfp pe_array_alpha_sqr_bfp_i (
        .a_dp8_i(a_dp8), .is_signed_b_i(is_signed_b),
        .alpha_sum_o(alpha_sum), .alpha_carry_o(alpha_carry)
    );

    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    function automatic longint alpha_gold(input int d);
        longint aa, ah, al, argh, argl;
        aa = 0;
        for (int ln = 0; ln < LANES; ln++) begin
            ah   = longint'($signed(a_dp8[d][ln*A_ELEM + B_ELEM +: B_ELEM]));
            al   = longint'($signed(a_dp8[d][ln*A_ELEM          +: B_ELEM]));
            argh = ah - (is_signed_b[d] ? 0 : 8);
            argl = al - (is_signed_b[d] ? 0 : 8);
            aa  += 16*(argh*argh) + (argl*argl);
        end
        return aa;
    endfunction

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) sel_a[p] = SEL_A[mi][p];
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = IS_SIGNED_A[mi][i];
            is_signed_b[i] = IS_SIGNED_B[mi][i];
            zero_dp8[i]    = ZERO_I_LUT[mi][i];
        end
    endtask

    task automatic rand_vec;
        for (int by = 0; by < PE_WIDTH/8; by++) begin
            int pa;
            pa = $urandom % 6;
            pe_in_a[by*8 +: 8] = (pa==0) ? 8'h00 : (pa==1) ? 8'hFF : (pa==2) ? 8'h80 :
                                 (pa==3) ? 8'h7F : (pa==4) ? 8'h88 : 8'($urandom);
        end
    endtask

    task automatic check(input int mi);
        longint got, exp;
        for (int d = 0; d < NUM_DP8; d++) begin
            got = longint'($signed(alpha_sum[d])) + longint'($signed(alpha_carry[d]));
            exp = -alpha_gold(d) - 2;
            if (got !== exp) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("MISMATCH mode=%0d dp8=%0d exp=%0d got=%0d", MODE_NUM[mi], d, exp, got);
                $fatal;
            end
        end
    endtask

    initial begin
        $display("\nStarting pe_array_alpha_sqr_bfp verification (%0d modes x %0d random)...\n", NUM_MODE, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_pe_array_alpha_sqr_bfp);
`endif
        rst_ni = 1'b0; pe_in_a = '0;
        for (int p = 0; p < NUM_PAIR; p++) sel_a[p] = '0;
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = 1'b1; is_signed_b[i] = 1'b1; zero_dp8[i] = 1'b0;
        end
        repeat (3) @(posedge clk_i);
        rst_ni = 1'b1;

        for (int mi = 0; mi < NUM_MODE; mi++) begin
            set_controls(mi);
            for (int t = 0; t < NUM_RAND; t++) begin
                rand_vec;
                @(posedge clk_i);
                #(T_SETTLE);
                check(mi);
            end
            $display("  mode %0d: PASS", MODE_NUM[mi]);
        end

`ifdef VCD
        $dumpoff;
`endif
        $display("\npe_array_alpha_sqr_bfp: all %0d modes x %0d random tests PASSED!\n", NUM_MODE, NUM_RAND);
        $finish;
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
