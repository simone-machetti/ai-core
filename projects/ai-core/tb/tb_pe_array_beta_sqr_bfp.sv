// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for pe_array_beta_sqr_bfp, driven through the real
//   square B dispatcher (disp_array_b_sqr). For each of the 11 modes it pushes
//   NUM_RAND corner-biased random 256-bit B operands, lets the dispatcher
//   center / idle-zero them, and checks every one of the 16 per-DP8 -beta
//   carry-save outputs against an independent software golden that replicates
//   dp_8_beta_sqr:
//       BETA_DP8 = 2^4 * sum_k arg_h(B_k)^2 + sum_k arg_l(B_k)^2 ,
//       arg_h(b) = signed(b) - 8*(~is_signed_a)   (gate_n_sqr, high block)
//       arg_l(b) = zero ? 0 : signed(b) - 8       (gate_n_beta_sqr, low block)
//   The module emits -beta via a one's-complement of the carry-save pair, so
//   each output pair resolves to -BETA_DP8 - 2 (the +2 folded downstream into
//   const_sqr_bfp). Idle DP8s (zero_i, B dispatcher-zeroed, is_signed_a = 1)
//   give BETA_DP8 = 0 -> resolve = -2. Reports a fatal error on any mismatch.
//
// Parameters:
//   NUM_RAND - number of random operand vectors per mode
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_pe_array_beta_sqr_bfp #(
    parameter int NUM_RAND = 500
);

    localparam real CLK_PERIOD = `CLK_PERIOD_NS;
    localparam real CLK_HALF   = CLK_PERIOD / 2.0;
    localparam real T_SETTLE   = CLK_PERIOD / 10.0;

    localparam int PE_WIDTH    = 256;
    localparam int NUM_PAIR    = 8;
    localparam int NUM_DP8     = 16;
    localparam int SEL_WIDTH   = 2;
    localparam int B_DP8_WIDTH = 32;
    localparam int B_ELEM      = 4;
    localparam int LANES       = 8;
    localparam int DP8_WIDTH   = 18;
    localparam int NUM_MODE    = 11;

    localparam int MODE_NUM [0:NUM_MODE-1] = '{1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12};

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
    logic [   PE_WIDTH-1:0] pe_in_b;
    logic [  SEL_WIDTH-1:0] sel_b       [0:NUM_PAIR-1];
    logic                   is_signed_a [ 0:NUM_DP8-1];
    logic                   is_signed_b [ 0:NUM_DP8-1];
    logic                   zero_dp8    [ 0:NUM_DP8-1];
    logic [B_DP8_WIDTH-1:0] b_dp8       [ 0:NUM_DP8-1];
    logic [  DP8_WIDTH-1:0] beta_sum    [ 0:NUM_DP8-1];
    logic [  DP8_WIDTH-1:0] beta_carry  [ 0:NUM_DP8-1];

    disp_array_b_sqr disp_array_b_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .pe_in_b_i(pe_in_b),
        .sel_b_i(sel_b), .is_signed_b_i(is_signed_b), .zero_i(zero_dp8),
        .b_dp8_o(b_dp8)
    );

    pe_array_beta_sqr_bfp pe_array_beta_sqr_bfp_i (
        .b_dp8_i(b_dp8), .is_signed_a_i(is_signed_a), .zero_i(zero_dp8),
        .beta_sum_o(beta_sum), .beta_carry_o(beta_carry)
    );

    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    function automatic longint beta_gold(input int d);
        longint bb, b, argh, argl;
        bb = 0;
        for (int ln = 0; ln < LANES; ln++) begin
            b    = longint'($signed(b_dp8[d][ln*B_ELEM +: B_ELEM]));
            argh = b - (is_signed_a[d] ? 0 : 8);
            argl = zero_dp8[d] ? 0 : (b - 8);
            bb  += 16*(argh*argh) + (argl*argl);
        end
        return bb;
    endfunction

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) sel_b[p] = SEL_B[mi][p];
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = IS_SIGNED_A[mi][i];
            is_signed_b[i] = IS_SIGNED_B[mi][i];
            zero_dp8[i]    = ZERO_I_LUT[mi][i];
        end
    endtask

    task automatic rand_vec;
        for (int by = 0; by < PE_WIDTH/8; by++) begin
            int pb;
            pb = $urandom % 6;
            pe_in_b[by*8 +: 8] = (pb==0) ? 8'h00 : (pb==1) ? 8'hFF : (pb==2) ? 8'h80 :
                                 (pb==3) ? 8'h7F : (pb==4) ? 8'h88 : 8'($urandom);
        end
    endtask

    task automatic check(input int mi);
        longint got, exp;
        for (int d = 0; d < NUM_DP8; d++) begin
            got = longint'($signed(beta_sum[d])) + longint'($signed(beta_carry[d]));
            exp = -beta_gold(d) - 2;
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
        $display("\nStarting pe_array_beta_sqr_bfp verification (%0d modes x %0d random)...\n", NUM_MODE, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_pe_array_beta_sqr_bfp);
`endif
        rst_ni = 1'b0; pe_in_b = '0;
        for (int p = 0; p < NUM_PAIR; p++) sel_b[p] = '0;
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
        $display("\npe_array_beta_sqr_bfp: all %0d modes x %0d random tests PASSED!\n", NUM_MODE, NUM_RAND);
        $finish;
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
