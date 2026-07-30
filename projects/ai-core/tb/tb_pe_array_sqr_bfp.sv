// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for pe_array_sqr_bfp, driven through the real
//   square dispatchers (disp_array_a_sqr / disp_array_b_sqr) and the square BFP
//   exponent dispatchers (disp_array_exp_a_sqr_bfp / disp_array_exp_b_sqr_bfp).
//   Gates 2 and 3 (the alpha/beta generators and const_sqr_bfp) are not built
//   yet, so the tb computes the -alpha / -beta carry-save and const_dp8_i itself
//   from the *dispatched* (centered) operands and drives the DUT's alpha/beta/
//   const ports. It uses the exact square identity
//       PE_j - alpha_j - beta_j = 2*P_j ,  P_j = sum_lanes(16*AH*b + AL*b)
//   so each DP8 leaf resolves to +/-2*P_j (negated blocks -> -2*P_j via the PE
//   comp_n plus the +2 in const). A small random per-DP8 K is added to const (and
//   to the golden leaf) to exercise the constant path at arbitrary magnitude.
//
//   Golden = the tb's own reduction of those leaves through the crossed tree
//   (radix shifts + exponent alignment), so the check exercises the DUT's L0
//   14:2 combine, the block negate, the exponent max-tree and the taps.
//
//   Two passes per mode. Pass A (equal exponents) -> every read-level tap
//   resolves bit-exact to the ideal reduction and every tap exponent equals the
//   subtree max. Pass B (distinct legal BFP exponents) -> tap exponents still
//   exact, and each read-level node value sits inside the truncation window
//   [ideal - allow, ideal] (the L0 window is widened to the 7-row bundle).
//   Corner-biased operands stress carry-save sign-consistency in the combine.
//
// Parameters:
//   NUM_RAND - number of random operand vectors per mode per pass
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_pe_array_sqr_bfp #(
    parameter int NUM_RAND = 300
);

    localparam real CLK_PERIOD = `CLK_PERIOD_NS;
    localparam real CLK_HALF   = CLK_PERIOD / 2.0;
    localparam real T_SETTLE   = CLK_PERIOD / 10.0;

    localparam int PE_WIDTH      = 256;
    localparam int NUM_BLK       = 4;
    localparam int NUM_PAIR      = 8;
    localparam int NUM_DP8       = 16;
    localparam int SEL_WIDTH     = 2;
    localparam int A_DP8_WIDTH   = 64;
    localparam int B_DP8_WIDTH   = 32;
    localparam int A_ELEM        = 8;
    localparam int B_ELEM        = 4;
    localparam int LANES         = 8;
    localparam int DP8_WIDTH     = 18;
    localparam int NUM_SHIFT     = 3;
    localparam int NUM_NEG       = 6;
    localparam int NUM_L0        = 8;
    localparam int NUM_L1        = 4;
    localparam int NUM_L2        = 2;
    localparam int SH0           = 8;
    localparam int SH1           = 4;
    localparam int SH2           = 8;
    localparam int L0_TAP_WIDTH  = 19;
    localparam int L1_TAP_WIDTH  = 30;
    localparam int L2_TAP_WIDTH  = 38;
    localparam int L3_TAP_WIDTH  = 39;
    localparam int EXP_IN_WIDTH  = 6;
    localparam int EXP_WIDTH     = 7;
    localparam int CHK_WIDTH     = 2 * EXP_IN_WIDTH;
    localparam int EXP_A_WIDTH   = NUM_BLK * EXP_IN_WIDTH;
    localparam int EXP_B_WIDTH   = NUM_BLK * CHK_WIDTH;
    localparam int NUM_MODE      = 11;

    localparam int MODE_NUM  [0:NUM_MODE-1] = '{1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12};
    localparam int TAP_LEVEL [0:NUM_MODE-1] = '{0, 1, 1, 2, 3, 2, 3, 2, 1, 2, 2};

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
        6'b000000, 6'b000000, 6'b000000, 6'b000000, 6'b000000, 6'b000000,
        6'b000000, 6'b000000, 6'b110011, 6'b001111, 6'b000000
    };

    localparam logic [NUM_SHIFT-1:0] SEL_SHIFT_LUT [0:NUM_MODE-1] = '{
        3'b000, 3'b010, 3'b011, 3'b000, 3'b010, 3'b011, 3'b111, 3'b111, 3'b010, 3'b010, 3'b111
    };

    localparam int EGRP_A [0:NUM_MODE-1][0:3] = '{
        '{0, 1, 2, 3}, '{0, 1, 2, 3}, '{0, 0, 1, 1}, '{0, 1, 2, 3}, '{0, 1, 2, 3},
        '{0, 0, 1, 1}, '{0, 0, 1, 1}, '{0, 0, 1, 1}, '{0, 0, 1, 1}, '{0, 0, 1, 1},
        '{0, 0, 1, 1}
    };

    localparam int EGRP_B [0:NUM_MODE-1][0:7] = '{
        '{0, 1, 0, 1, 2, 3, 2, 3},
        '{0, 0, 1, 1, 2, 2, 3, 3},
        '{0, 0, 1, 1, 2, 2, 3, 3},
        '{0, 2, 0, 2, 1, 3, 1, 3},
        '{0, 0, 1, 1, 2, 2, 3, 3},
        '{0, 0, 1, 1, 2, 2, 3, 3},
        '{0, 0, 0, 0, 1, 1, 1, 1},
        '{0, 0, 0, 0, 1, 1, 1, 1},
        '{0, 0, 0, 0, 1, 1, 1, 1},
        '{0, 0, 0, 0, 1, 1, 1, 1},
        '{0, 0, 0, 0, 0, 0, 0, 0}
    };

    logic                     clk_i;
    logic                     rst_ni;
    logic [    PE_WIDTH-1:0]  pe_in_a;
    logic [    PE_WIDTH-1:0]  pe_in_b;
    logic [ EXP_A_WIDTH-1:0]  pe_exp_a;
    logic [ EXP_B_WIDTH-1:0]  pe_exp_b;
    logic [   SEL_WIDTH-1:0]  sel_a       [0:NUM_PAIR-1];
    logic [   SEL_WIDTH-1:0]  sel_b       [0:NUM_PAIR-1];
    logic                     is_signed_a [ 0:NUM_DP8-1];
    logic                     is_signed_b [ 0:NUM_DP8-1];
    logic                     zero_dp8    [ 0:NUM_DP8-1];
    logic [     NUM_NEG-1:0]  neg;
    logic [   NUM_SHIFT-1:0]  sel_shift;
    logic [             2:0]  en_level;

    logic [ A_DP8_WIDTH-1:0]  a_dp8       [ 0:NUM_DP8-1];
    logic [ B_DP8_WIDTH-1:0]  b_dp8       [ 0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0]  exp_a_dp8   [ 0:NUM_DP8-1];
    logic [EXP_IN_WIDTH-1:0]  exp_b_dp8   [ 0:NUM_DP8-1];

    logic [   DP8_WIDTH-1:0]  alpha_sum   [ 0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0]  alpha_carry [ 0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0]  beta_sum    [ 0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0]  beta_carry  [ 0:NUM_DP8-1];
    logic [   DP8_WIDTH-1:0]  const_dp8   [ 0:NUM_DP8-1];

    logic [L0_TAP_WIDTH-1:0]  l0_sum      [  0:NUM_L0-1];
    logic [L0_TAP_WIDTH-1:0]  l0_carry    [  0:NUM_L0-1];
    logic [   EXP_WIDTH-1:0]  l0_exp      [  0:NUM_L0-1];
    logic [L1_TAP_WIDTH-1:0]  l1_sum      [  0:NUM_L1-1];
    logic [L1_TAP_WIDTH-1:0]  l1_carry    [  0:NUM_L1-1];
    logic [   EXP_WIDTH-1:0]  l1_exp      [  0:NUM_L1-1];
    logic [L2_TAP_WIDTH-1:0]  l2_sum      [  0:NUM_L2-1];
    logic [L2_TAP_WIDTH-1:0]  l2_carry    [  0:NUM_L2-1];
    logic [   EXP_WIDTH-1:0]  l2_exp      [  0:NUM_L2-1];
    logic [L3_TAP_WIDTH-1:0]  l3_sum;
    logic [L3_TAP_WIDTH-1:0]  l3_carry;
    logic [   EXP_WIDTH-1:0]  l3_exp;

    logic [   EXP_WIDTH-1:0] gold_exp_a   [ 0:NUM_DP8-1];
    logic [   EXP_WIDTH-1:0] gold_exp_b   [ 0:NUM_DP8-1];
    logic [   EXP_WIDTH-1:0] exp_dp8_g    [ 0:NUM_DP8-1];
    longint                  dleaf        [ 0:NUM_DP8-1];
    int                      err;
    int                      npass;

    disp_array_a_sqr disp_array_a_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .pe_in_a_i(pe_in_a),
        .sel_a_i(sel_a), .is_signed_a_i(is_signed_a), .zero_i(zero_dp8), .a_dp8_o(a_dp8)
    );

    disp_array_b_sqr disp_array_b_sqr_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .pe_in_b_i(pe_in_b),
        .sel_b_i(sel_b), .is_signed_b_i(is_signed_b), .zero_i(zero_dp8), .b_dp8_o(b_dp8)
    );

    disp_array_exp_a_sqr_bfp disp_array_exp_a_sqr_bfp_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .pe_exp_a_i(pe_exp_a),
        .sel_a_i(sel_a), .zero_i(zero_dp8), .exp_a_dp8_o(exp_a_dp8)
    );

    disp_array_exp_b_sqr_bfp disp_array_exp_b_sqr_bfp_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .pe_exp_b_i(pe_exp_b),
        .sel_b_i(sel_b), .zero_i(zero_dp8), .exp_b_dp8_o(exp_b_dp8)
    );

    pe_array_sqr_bfp pe_array_sqr_bfp_i (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .a_dp8_i(a_dp8), .b_dp8_i(b_dp8),
        .alpha_sum_i(alpha_sum), .alpha_carry_i(alpha_carry),
        .beta_sum_i(beta_sum), .beta_carry_i(beta_carry),
        .const_dp8_i(const_dp8), .neg_i(neg),
        .exp_a_dp8_i(exp_a_dp8), .exp_b_dp8_i(exp_b_dp8),
        .sel_shift_i(sel_shift), .en_level_i(en_level),
        .l0_sum_o(l0_sum), .l0_carry_o(l0_carry), .l0_exp_o(l0_exp),
        .l1_sum_o(l1_sum), .l1_carry_o(l1_carry), .l1_exp_o(l1_exp),
        .l2_sum_o(l2_sum), .l2_carry_o(l2_carry), .l2_exp_o(l2_exp),
        .l3_sum_o(l3_sum), .l3_carry_o(l3_carry), .l3_exp_o(l3_exp)
    );

    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    function automatic longint resolve_tap(input int lvl, input int node);
        case (lvl)
            0:       return longint'($signed(l0_sum[node])) + longint'($signed(l0_carry[node]));
            1:       return longint'($signed(l1_sum[node])) + longint'($signed(l1_carry[node]));
            2:       return longint'($signed(l2_sum[node])) + longint'($signed(l2_carry[node]));
            default: return longint'($signed(l3_sum))       + longint'($signed(l3_carry));
        endcase
    endfunction

    function automatic logic [EXP_WIDTH-1:0] exp_tap(input int lvl, input int node);
        case (lvl)
            0:       return l0_exp[node];
            1:       return l1_exp[node];
            2:       return l2_exp[node];
            default: return l3_exp;
        endcase
    endfunction

    function automatic bit insub(input int d, input int lvl, input int node);
        int n;
        n = 2*(d/4) + (d%2);
        case (lvl)
            0:       return (n == node);
            1:       return (n/2 == node);
            2:       return (n/4 == node);
            default: return 1'b1;
        endcase
    endfunction

    function automatic logic [EXP_WIDTH-1:0] egold(input int lvl, input int node);
        logic [EXP_WIDTH-1:0] e;
        e = '0;
        for (int d = 0; d < NUM_DP8; d++)
            if (insub(d, lvl, node) && exp_dp8_g[d] > e) e = exp_dp8_g[d];
        return e;
    endfunction

    function automatic longint fdiv(input longint x, input int k);
        int kk;
        kk = (k > 63) ? 63 : k;
        return x >>> kk;
    endfunction

    longint gv_l0 [0:NUM_L0-1];  longint gd_l0 [0:NUM_L0-1];
    longint gv_l1 [0:NUM_L1-1];  longint gd_l1 [0:NUM_L1-1];
    longint gv_l2 [0:NUM_L2-1];  longint gd_l2 [0:NUM_L2-1];
    longint gv_l3;               longint gd_l3;

    localparam int L0_ROWS = 7;

    task automatic cascade_golden();
        int s0, s1, s2, cx0, cx1, e, dhi, dlo;
        longint vhi, dh, dl;
        s0 = sel_shift[0] ? SH0 : 0;
        s1 = sel_shift[1] ? SH1 : 0;
        s2 = sel_shift[2] ? SH2 : 0;
        for (int n = 0; n < NUM_L0; n++) begin
            cx0 = 4*(n/2) + (n%2);
            cx1 = cx0 + 2;
            e   = int'(egold(0, n));
            dhi = e - int'(exp_dp8_g[cx0]);
            dlo = e - int'(exp_dp8_g[cx1]);
            gv_l0[n] = fdiv(dleaf[cx0] <<< s0, dhi) + fdiv(dleaf[cx1], dlo);
            gd_l0[n] = longint'((dhi > 0) ? L0_ROWS : 0) + longint'((dlo > 0) ? L0_ROWS : 0);
        end
        for (int j = 0; j < NUM_L1; j++) begin
            gv_l1[j] = (gv_l0[2*j] <<< s1) + gv_l0[2*j+1];
            gd_l1[j] = (gd_l0[2*j] <<< s1) + gd_l0[2*j+1];
        end
        for (int k = 0; k < NUM_L2; k++) begin
            e   = int'(egold(2, k));
            dhi = e - int'(egold(1, 2*k));
            dlo = e - int'(egold(1, 2*k+1));
            vhi = gv_l1[2*k] <<< s2;
            dh  = gd_l1[2*k] <<< s2;
            dl  = gd_l1[2*k+1];
            gv_l2[k] = fdiv(vhi, dhi) + fdiv(gv_l1[2*k+1], dlo);
            gd_l2[k] = ((dhi > 0) ? (fdiv(dh, dhi) + 2) : dh)
                     + ((dlo > 0) ? (fdiv(dl, dlo) + 2) : dl);
        end
        begin
            e   = int'(egold(3, 0));
            dhi = e - int'(egold(2, 0));
            dlo = e - int'(egold(2, 1));
            gv_l3 = fdiv(gv_l2[0], dhi) + fdiv(gv_l2[1], dlo);
            gd_l3 = ((dhi > 0) ? (fdiv(gd_l2[0], dhi) + 2) : gd_l2[0])
                  + ((dlo > 0) ? (fdiv(gd_l2[1], dlo) + 2) : gd_l2[1]);
        end
    endtask

    function automatic int ebias(input int base);
        int d;
        case ($urandom_range(0, 7))
            0: d = 0; 1: d = 1; 2: d = 7; 3: d = 8; 4: d = 27; 5: d = 28; 6: d = 56;
            default: d = int'($urandom_range(0, 63));
        endcase
        if ($urandom_range(0, 1) == 1) d = -d;
        d = base + d;
        if (d < 0) d = 0;
        if (d > 63) d = 63;
        return d;
    endfunction

    task automatic set_exps(input int mi, input bit equal);
        int base;
        int ga [0:3];
        int gb [0:7];
        logic [5:0] ea [0:3];
        logic [5:0] eb [0:7];
        base = int'($urandom_range(0, 63));
        for (int g = 0; g < 4; g++) ga[g] = equal ? base : ebias(base);
        for (int g = 0; g < 8; g++) gb[g] = equal ? base : ebias(base);
        for (int blk = 0; blk < 4; blk++) ea[blk] = 6'(ga[EGRP_A[mi][blk]]);
        for (int h = 0; h < 8; h++)      eb[h]   = 6'(gb[EGRP_B[mi][h]]);
        for (int blk = 0; blk < NUM_BLK; blk++) begin
            pe_exp_a[blk*EXP_IN_WIDTH +: EXP_IN_WIDTH]           = ea[blk];
            pe_exp_b[blk*CHK_WIDTH+EXP_IN_WIDTH +: EXP_IN_WIDTH] = eb[2*blk];
            pe_exp_b[blk*CHK_WIDTH +: EXP_IN_WIDTH]              = eb[2*blk+1];
        end
        for (int p = 0; p < NUM_PAIR; p++) begin
            gold_exp_a[2*p]   = zero_dp8[2*p]   ? '0 : EXP_WIDTH'(ea[SEL_A[mi][p]]);
            gold_exp_b[2*p]   = zero_dp8[2*p]   ? '0 : EXP_WIDTH'(eb[int'(SEL_B[mi][p])*2]);
            gold_exp_a[2*p+1] = zero_dp8[2*p+1] ? '0 : EXP_WIDTH'(ea[SEL_A[mi][p]]);
            gold_exp_b[2*p+1] = zero_dp8[2*p+1] ? '0 : EXP_WIDTH'(eb[int'(SEL_B[mi][p])*2+1]);
        end
        for (int i = 0; i < NUM_DP8; i++)
            exp_dp8_g[i] = gold_exp_a[i] + gold_exp_b[i];
    endtask

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_A[mi][p];
            sel_b[p] = SEL_B[mi][p];
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = IS_SIGNED_A[mi][i];
            is_signed_b[i] = IS_SIGNED_B[mi][i];
            zero_dp8[i]    = ZERO_I_LUT[mi][i];
        end
        neg       = NEG_I[mi];
        sel_shift = SEL_SHIFT_LUT[mi];
        en_level  = {TAP_LEVEL[mi] >= 3, TAP_LEVEL[mi] >= 2, TAP_LEVEL[mi] >= 1};
    endtask

    task automatic rand_vec;
        for (int by = 0; by < PE_WIDTH/8; by++) begin
            int pa, pb;
            pa = $urandom % 6;
            pb = $urandom % 6;
            pe_in_a[by*8 +: 8] = (pa==0) ? 8'h00 : (pa==1) ? 8'hFF : (pa==2) ? 8'h80 :
                                 (pa==3) ? 8'h7F : (pa==4) ? 8'h88 : 8'($urandom);
            pe_in_b[by*8 +: 8] = (pb==0) ? 8'h00 : (pb==1) ? 8'hFF : (pb==2) ? 8'h80 :
                                 (pb==3) ? 8'h7F : (pb==4) ? 8'h88 : 8'($urandom);
        end
    endtask

    task automatic drive_ab_const(input int mi);
        logic negd [0:NUM_DP8-1];
        for (int i = 0; i < NUM_DP8; i++) negd[i] = 1'b0;
        negd[2]  = NEG_I[mi][0]; negd[3]  = NEG_I[mi][1];
        negd[6]  = NEG_I[mi][2]; negd[7]  = NEG_I[mi][3];
        negd[10] = NEG_I[mi][4]; negd[11] = NEG_I[mi][5];

        for (int d = 0; d < NUM_DP8; d++) begin
            longint pp, aa, bbq;
            int     kk;
            pp = 0; aa = 0; bbq = 0;
            for (int ln = 0; ln < LANES; ln++) begin
                longint ah, al, bb;
                ah  = longint'($signed(a_dp8[d][ln*A_ELEM + B_ELEM +: B_ELEM]));
                al  = longint'($signed(a_dp8[d][ln*A_ELEM          +: B_ELEM]));
                bb  = longint'($signed(b_dp8[d][ln*B_ELEM          +: B_ELEM]));
                pp  += 16*(ah*bb) + (al*bb);
                aa  += 16*(ah*ah) + (al*al);
                bbq += 16*(bb*bb) + (bb*bb);
            end
            kk = int'($urandom_range(0, 511)) - 256;
            if (zero_dp8[d]) begin
                alpha_sum[d]   = '0;
                beta_sum[d]    = '0;
                const_dp8[d]   = '0;
                dleaf[d]       = 0;
            end else begin
                alpha_sum[d]   = DP8_WIDTH'(-aa);
                beta_sum[d]    = DP8_WIDTH'(-bbq);
                const_dp8[d]   = DP8_WIDTH'((negd[d] ? 6 : 0) + kk);
                dleaf[d]       = (negd[d] ? -2*pp : 2*pp) + kk;
            end
            alpha_carry[d] = '0;
            beta_carry[d]  = '0;
        end
    endtask

    task automatic check_exps(input int mi);
        for (int n = 0; n < NUM_L0; n++)
            if (l0_exp[n] !== egold(0, n)) begin
                err++; $display("mode %0d L0[%0d] exp: dut %0d gold %0d", MODE_NUM[mi], n, l0_exp[n], egold(0,n));
            end
        for (int j = 0; j < NUM_L1; j++)
            if (l1_exp[j] !== egold(1, j)) begin
                err++; $display("mode %0d L1[%0d] exp: dut %0d gold %0d", MODE_NUM[mi], j, l1_exp[j], egold(1,j));
            end
        for (int k = 0; k < NUM_L2; k++)
            if (l2_exp[k] !== egold(2, k)) begin
                err++; $display("mode %0d L2[%0d] exp: dut %0d gold %0d", MODE_NUM[mi], k, l2_exp[k], egold(2,k));
            end
        if (l3_exp !== egold(3, 0)) begin
            err++; $display("mode %0d L3 exp: dut %0d gold %0d", MODE_NUM[mi], l3_exp, egold(3,0));
        end
    endtask

    task automatic check_value(input int mi, input bit equal);
        longint r, ideal, allow;
        int lvl, nn;
        lvl = TAP_LEVEL[mi];
        nn  = (lvl == 0) ? NUM_L0 : (lvl == 1) ? NUM_L1 : (lvl == 2) ? NUM_L2 : 1;
        cascade_golden();
        for (int node = 0; node < nn; node++) begin
            r = resolve_tap(lvl, node);
            case (lvl)
                0: begin ideal = gv_l0[node]; allow = gd_l0[node]; end
                1: begin ideal = gv_l1[node]; allow = gd_l1[node]; end
                2: begin ideal = gv_l2[node]; allow = gd_l2[node]; end
                default: begin ideal = gv_l3; allow = gd_l3; end
            endcase
            if (equal) begin
                if (r !== ideal) begin
                    err++; $display("mode %0d L%0d[%0d] EQ value: dut %0d ideal %0d", MODE_NUM[mi], lvl, node, r, ideal);
                end
            end else begin
                if (r > ideal || r < ideal - allow - 1) begin
                    err++; $display("mode %0d L%0d[%0d] window: dut %0d ideal %0d allow %0d",
                                    MODE_NUM[mi], lvl, node, r, ideal, allow);
                end
            end
        end
    endtask

    task automatic run_vec(input int mi, input bit equal);
        set_exps(mi, equal);
        @(posedge clk_i);
        #(T_SETTLE);
        drive_ab_const(mi);
        #(T_SETTLE);
        @(posedge clk_i);
        #(T_SETTLE);
        check_exps(mi);
        check_value(mi, equal);
    endtask

    initial begin
        int err0;
        $display("\nStarting pe_array_sqr_bfp verification (%0d modes x %0d random x 2 passes)...\n", NUM_MODE, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_pe_array_sqr_bfp);
`endif
        rst_ni = 1'b0; pe_in_a = '0; pe_in_b = '0; pe_exp_a = '0; pe_exp_b = '0;
        for (int p = 0; p < NUM_PAIR; p++) begin sel_a[p] = '0; sel_b[p] = '0; end
        for (int i = 0; i < NUM_DP8; i++) begin
            is_signed_a[i] = 1'b1; is_signed_b[i] = 1'b1; zero_dp8[i] = 1'b0;
            alpha_sum[i] = '0; alpha_carry[i] = '0; beta_sum[i] = '0; beta_carry[i] = '0;
            const_dp8[i] = '0; gold_exp_a[i] = '0; gold_exp_b[i] = '0; exp_dp8_g[i] = '0;
        end
        neg = '0; sel_shift = '0; en_level = '1; err = 0; npass = 0;
        repeat (3) @(posedge clk_i);
        rst_ni = 1'b1;

        for (int mi = 0; mi < NUM_MODE; mi++) begin
            set_controls(mi);
            err0 = err;
            for (int t = 0; t < NUM_RAND; t++) begin
                rand_vec; run_vec(mi, 1'b1);
                rand_vec; run_vec(mi, 1'b0);
            end
            if (err == err0) begin
                npass++; $display("  mode %0d: PASS", MODE_NUM[mi]);
            end else
                $display("  mode %0d: FAIL (%0d mismatches)", MODE_NUM[mi], err - err0);
        end

`ifdef VCD
        $dumpoff;
`endif
        $display("\npe_array_sqr_bfp: %0d/%0d modes passed (%0d total mismatches)\n", npass, NUM_MODE, err);
        $finish;
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
