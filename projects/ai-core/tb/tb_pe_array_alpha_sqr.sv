// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for pe_array_alpha_sqr, driven through the square A
//   dispatcher (disp_array_a_sqr), mirroring tb_pe_array_sqr's disp -> array
//   structure. For each of the 11 modes it pushes NUM_RAND corner-biased random
//   256-bit A operands, lets the dispatcher center/idle-zero them, and checks
//   every tap at the mode's read level against a golden that recomputes the
//   tree: ALPHA_DP8 per DP8 from the dispatched (centered) A operand and the
//   removed-B -8 bias (is_signed_b), the complex-mode block negate (a negated
//   block resolves to -ALPHA_DP8-2, the deferred +2 being acc_array_sqr's job),
//   then the crossed 4-level weighted sum. Reports a fatal error on any mismatch.
//
//   ALPHA_DP8 = sum_k 16*(AH_k - 8*bu)^2 + (AL_k - 8*bu)^2, bu = ~is_signed_b.
//   Idle DP8s are clean via is_signed_b = 1 on a dispatcher-zeroed A. This
//   verifies the alpha DP8 bias (gate_n_sqr) + the shared tree; the +2 and the
//   alpha/beta/C reconstruction are the accumulator's concern (later gate).
//
// Parameters:
//   NUM_RAND - number of random operand vectors per mode
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_pe_array_alpha_sqr #(
    parameter int NUM_RAND = 200
);

    localparam int PE_WIDTH     = 256;
    localparam int NUM_PAIR     = 8;
    localparam int NUM_DP8      = 16;
    localparam int SEL_WIDTH    = 2;
    localparam int A_DP8_WIDTH  = 64;
    localparam int A_ELEM       = 8;
    localparam int B_ELEM       = 4;
    localparam int LANES        = 8;
    localparam int NUM_SHIFT    = 3;
    localparam int NUM_NEG      = 6;
    localparam int NUM_L0       = 8;
    localparam int NUM_L1       = 4;
    localparam int NUM_L2       = 2;
    localparam int SH0          = 8;
    localparam int SH1          = 4;
    localparam int SH2          = 8;
    localparam int L0_TAP_WIDTH = 19;
    localparam int L1_TAP_WIDTH = 30;
    localparam int L2_TAP_WIDTH = 38;
    localparam int L3_TAP_WIDTH = 39;
    localparam int NUM_MODE     = 11;

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

    localparam logic [NUM_NEG-1:0] NEG_I [0:NUM_MODE-1] = '{
        6'b000000,
        6'b000000,
        6'b000000,
        6'b000000,
        6'b000000,
        6'b000000,
        6'b000000,
        6'b000000,
        6'b110011,
        6'b001111,
        6'b000000
    };

    localparam logic [NUM_SHIFT-1:0] SEL_SHIFT_LUT [0:NUM_MODE-1] = '{
        3'b000, 3'b010, 3'b011, 3'b000, 3'b010, 3'b011, 3'b111, 3'b111, 3'b010, 3'b010, 3'b111
    };

    localparam int TAP_LEVEL [0:NUM_MODE-1] = '{0, 1, 1, 2, 3, 2, 3, 2, 1, 2, 2};

    logic                    clk_i;
    logic                    rst_ni;
    logic [   PE_WIDTH-1:0]  pe_in_a;
    logic [  SEL_WIDTH-1:0]  sel_a       [0:NUM_PAIR-1];
    logic                    is_signed_a [0:NUM_DP8-1];
    logic                    is_signed_b [0:NUM_DP8-1];
    logic                    zero_dp8    [0:NUM_DP8-1];
    logic [    NUM_NEG-1:0]  neg;
    logic [  NUM_SHIFT-1:0]  sel_shift;
    logic [A_DP8_WIDTH-1:0]  a_dp8       [0:NUM_DP8-1];
    logic [L0_TAP_WIDTH-1:0] l0_sum      [0:NUM_L0-1];
    logic [L0_TAP_WIDTH-1:0] l0_carry    [0:NUM_L0-1];
    logic [L1_TAP_WIDTH-1:0] l1_sum      [0:NUM_L1-1];
    logic [L1_TAP_WIDTH-1:0] l1_carry    [0:NUM_L1-1];
    logic [L2_TAP_WIDTH-1:0] l2_sum      [0:NUM_L2-1];
    logic [L2_TAP_WIDTH-1:0] l2_carry    [0:NUM_L2-1];
    logic [L3_TAP_WIDTH-1:0] l3_sum;
    logic [L3_TAP_WIDTH-1:0] l3_carry;

    disp_array_a_sqr disp_array_a_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .pe_in_a_i(pe_in_a),
        .sel_a_i(sel_a), .is_signed_a_i(is_signed_a), .zero_i(zero_dp8),
        .a_dp8_o(a_dp8)
    );

    pe_array_alpha_sqr pe_array_alpha_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .a_dp8_i(a_dp8), .is_signed_b_i(is_signed_b),
        .neg_i(neg), .sel_shift_i(sel_shift),
        .l0_sum_o(l0_sum), .l0_carry_o(l0_carry),
        .l1_sum_o(l1_sum), .l1_carry_o(l1_carry),
        .l2_sum_o(l2_sum), .l2_carry_o(l2_carry),
        .l3_sum_o(l3_sum), .l3_carry_o(l3_carry)
    );

    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    function automatic longint adp8(input logic [A_DP8_WIDTH-1:0] a, input logic isb);
        longint s;
        s = 0;
        for (int ln = 0; ln < LANES; ln++) begin
            longint ah, al, aah, aal;
            ah  = longint'($signed(a[ln*A_ELEM + B_ELEM +: B_ELEM]));
            al  = longint'($signed(a[ln*A_ELEM          +: B_ELEM]));
            aah = isb ? ah : ah - 8;
            aal = isb ? al : al - 8;
            s  += 16*(aah*aah) + (aal*aal);
        end
        return s;
    endfunction

    function automatic longint resolve_tap(input int lvl, input int node);
        case (lvl)
            0:       return longint'($signed(l0_sum[node])) + longint'($signed(l0_carry[node]));
            1:       return longint'($signed(l1_sum[node])) + longint'($signed(l1_carry[node]));
            2:       return longint'($signed(l2_sum[node])) + longint'($signed(l2_carry[node]));
            default: return longint'($signed(l3_sum))       + longint'($signed(l3_carry));
        endcase
    endfunction

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) sel_a[p] = SEL_A[mi][p];
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = IS_SIGNED_A[mi][i];
            is_signed_b[i] = IS_SIGNED_B[mi][i];
            zero_dp8[i]    = ZERO_I_LUT[mi][i];
        end
        neg       = NEG_I[mi];
        sel_shift = SEL_SHIFT_LUT[mi];
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
        longint sd  [0:NUM_DP8-1];
        longint blk [0:NUM_DP8-1];
        longint l0e [0:NUM_L0-1];
        longint l1e [0:NUM_L1-1];
        longint l2e [0:NUM_L2-1];
        longint l3e;
        logic   negd [0:NUM_DP8-1];
        longint got, exp;
        int lvl;

        for (int i = 0; i < NUM_DP8; i++) negd[i] = 1'b0;
        negd[2]  = NEG_I[mi][0]; negd[3]  = NEG_I[mi][1];
        negd[6]  = NEG_I[mi][2]; negd[7]  = NEG_I[mi][3];
        negd[10] = NEG_I[mi][4]; negd[11] = NEG_I[mi][5];

        for (int i = 0; i < NUM_DP8; i++) begin
            sd[i]  = adp8(a_dp8[i], is_signed_b[i]);
            blk[i] = negd[i] ? (-sd[i] - 2) : sd[i];
        end

        for (int n = 0; n < NUM_L0; n++) begin
            int cx0, cx1;
            cx0 = 4*(n/2) + (n%2); cx1 = cx0 + 2;
            l0e[n] = (SEL_SHIFT_LUT[mi][0] ? blk[cx0]*(1<<SH0) : blk[cx0]) + blk[cx1];
        end
        for (int j = 0; j < NUM_L1; j++)
            l1e[j] = (SEL_SHIFT_LUT[mi][1] ? l0e[2*j]*(1<<SH1) : l0e[2*j]) + l0e[2*j+1];
        for (int kk = 0; kk < NUM_L2; kk++)
            l2e[kk] = (SEL_SHIFT_LUT[mi][2] ? l1e[2*kk]*(1<<SH2) : l1e[2*kk]) + l1e[2*kk+1];
        l3e = l2e[0] + l2e[1];

        lvl = TAP_LEVEL[mi];
        for (int node = 0; node < (1 << (3-lvl)); node++) begin
            got = resolve_tap(lvl, node);
            case (lvl)
                0:       exp = l0e[node];
                1:       exp = l1e[node];
                2:       exp = l2e[node];
                default: exp = l3e;
            endcase
            if (got !== exp) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("MISMATCH mode=%0d lvl=%0d node=%0d exp=%0d got=%0d", MODE_NUM[mi], lvl, node, exp, got);
                $fatal;
            end
        end
    endtask

    initial begin
        $display("\nStarting pe_array_alpha_sqr verification (%0d modes x %0d random)...\n", NUM_MODE, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_pe_array_alpha_sqr.pe_array_alpha_sqr_i);
`endif

        rst_ni  = 1'b0;
        pe_in_a = '0;
        for (int p = 0; p < NUM_PAIR; p++) sel_a[p] = '0;
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = 1'b1; is_signed_b[i] = 1'b1; zero_dp8[i] = 1'b0;
        end
        neg = '0; sel_shift = '0;
        repeat (3) @(posedge clk_i);
        rst_ni = 1'b1;

        for (int mi = 0; mi < NUM_MODE; mi++) begin
            set_controls(mi);
            for (int t = 0; t < NUM_RAND; t++) begin
                rand_vec;
                repeat (2) @(posedge clk_i);
                #1;
                check(mi);
            end
            $display("  mode %0d: PASS", MODE_NUM[mi]);
        end

`ifdef VCD
        $dumpoff;
`endif
        $display("\npe_array_alpha_sqr: all %0d modes x %0d random tests PASSED!\n", NUM_MODE, NUM_RAND);
        $finish;
    end

endmodule
