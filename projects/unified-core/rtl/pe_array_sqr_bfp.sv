// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Square + BFP PE array. Same exponent-aligned crossed tree as pe_array_bfp,
//   with a square reconstruction FRONT-END: 16 dp_8_sqr produce the PE
//   square-sums, and the per-row -alpha / per-column -beta carry-save pairs plus
//   the per-DP8 constant const_dp8_i are folded into 2*P PER DP8, before the
//   crossed tree. Each DP8's mantissa lives in its own scale E_j = e_A,j + e_B,j,
//   so the {PE, -alpha, -beta, C} reduction needs no alignment: a per-DP8 7:2 CPR
//   (cpr_w_n IN_SIZE=7) collapses the six-row {PE, -alpha, -beta} bundle plus the
//   const row to a single carry-save pair 2*P at the block scale. This front-end
//   is the ext_inject_sqr_bfp block (one instantiation over all NUM_DP8 DP8s).
//
//   Block negate (modes 10/11): comp_n one's-complements the six-row
//   {PE, -alpha, -beta} bundle of the NEGATED DP8s (2,3,6,7,10,11) inside
//   ext_inject_sqr_bfp; the const row stays un-negated and carries the per-DP8
//   constant (absorbing the six +1 deferrals) - exactly as before. So the
//   alpha/beta generators stay neg-agnostic and const_sqr_bfp is UNCHANGED;
//   neg_i (indexed by L0 node) is mapped back to the per-DP8 index here.
//
//   From the 7:2 outputs onward the tree is baseline-BFP verbatim on two-row DP8
//   pairs: L0 crosses two DP8s under their own scales (shift <<8, ext,
//   align_cell_bfp SIZE_0=SIZE_1=2, 4:2 CPR); L1 (no align, exponent max forward),
//   L2 and L3 (align), the exponent max-tree and the per-level taps are
//   pe_array_bfp verbatim. Because 2*P is formed per DP8 before the shift/align
//   and both are linear and uniform per block, this is a pure REASSOCIATION of the
//   previous fused 14:2 node - the l0..l3 taps are bit-identical.
//
//   Widths: the square-sum leaves are DP8_WIDTH-bit; the per-DP8 2*P is
//   P_WIDTH = DP8_WIDTH + clog2(NUM_ROW) = 21-bit, the clog2(7) headroom keeping
//   the 7:2 output sign-consistent for the crossed-tree sign-extension. Node
//   widths follow (L0..L3 = 29/33/41/42); the taps are unchanged (their low
//   19/30/38/39 bits carry the same 2*P value). EXP_WIDTH = 7 holds e_A + e_B
//   exactly. The per-DP8 7:2 and the crossed shift/ext/align run IS_SIGNED (2*P
//   carries signed -alpha/-beta/C and the negated PE).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_array_sqr_bfp #(
    localparam int NUM_DP8      = 16,
    localparam int A_DP8_WIDTH  = 64,
    localparam int B_DP8_WIDTH  = 32,
    localparam int LANES        = 8,
    localparam int IN_WIDTH_A   = 8,
    localparam int IN_WIDTH_B   = 4,
    localparam int DP8_WIDTH    = 18,
    localparam int NUM_ROW      = 7,
    localparam int NUM_SHIFT    = 3,
    localparam int NUM_LEVEL    = 3,
    localparam int NUM_L0       = 8,
    localparam int NUM_L1       = 4,
    localparam int NUM_L2       = 2,
    localparam int NUM_NEG      = 6,
    localparam int SH0          = 8,
    localparam int SH1          = 4,
    localparam int SH2          = 8,
    localparam int P_WIDTH      = DP8_WIDTH + $clog2(NUM_ROW),
    localparam int L0_WIDTH     = P_WIDTH   + SH0,
    localparam int L1_WIDTH     = L0_WIDTH  + SH1,
    localparam int L2_WIDTH     = L1_WIDTH  + SH2,
    localparam int L3_EXT       = 1,
    localparam int L3_WIDTH     = L2_WIDTH  + L3_EXT,
    localparam int L0_TAP_WIDTH = 19,
    localparam int L1_TAP_WIDTH = 30,
    localparam int L2_TAP_WIDTH = 38,
    localparam int L3_TAP_WIDTH = 39,
    localparam int EXP_IN_WIDTH = 6,
    localparam int EXP_WIDTH    = EXP_IN_WIDTH + 1
)(
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic [ A_DP8_WIDTH-1:0] a_dp8_i       [0:NUM_DP8-1],
    input  logic [ B_DP8_WIDTH-1:0] b_dp8_i       [0:NUM_DP8-1],
    input  logic [   DP8_WIDTH-1:0] alpha_sum_i   [0:NUM_DP8-1],
    input  logic [   DP8_WIDTH-1:0] alpha_carry_i [0:NUM_DP8-1],
    input  logic [   DP8_WIDTH-1:0] beta_sum_i    [0:NUM_DP8-1],
    input  logic [   DP8_WIDTH-1:0] beta_carry_i  [0:NUM_DP8-1],
    input  logic [   DP8_WIDTH-1:0] const_dp8_i   [0:NUM_DP8-1],
    input  logic [     NUM_NEG-1:0] neg_i,
    input  logic                    zero_i        [0:NUM_DP8-1],
    input  logic [EXP_IN_WIDTH-1:0] exp_a_dp8_i   [0:NUM_DP8-1],
    input  logic [EXP_IN_WIDTH-1:0] exp_b_dp8_i   [0:NUM_DP8-1],
    input  logic [   NUM_SHIFT-1:0] sel_shift_i,
    input  logic [   NUM_LEVEL-1:0] en_level_i,
    output logic [L0_TAP_WIDTH-1:0] l0_sum_o      [0:NUM_L0-1],
    output logic [L0_TAP_WIDTH-1:0] l0_carry_o    [0:NUM_L0-1],
    output logic [   EXP_WIDTH-1:0] l0_exp_o      [0:NUM_L0-1],
    output logic [L1_TAP_WIDTH-1:0] l1_sum_o      [0:NUM_L1-1],
    output logic [L1_TAP_WIDTH-1:0] l1_carry_o    [0:NUM_L1-1],
    output logic [   EXP_WIDTH-1:0] l1_exp_o      [0:NUM_L1-1],
    output logic [L2_TAP_WIDTH-1:0] l2_sum_o      [0:NUM_L2-1],
    output logic [L2_TAP_WIDTH-1:0] l2_carry_o    [0:NUM_L2-1],
    output logic [   EXP_WIDTH-1:0] l2_exp_o      [0:NUM_L2-1],
    output logic [L3_TAP_WIDTH-1:0] l3_sum_o,
    output logic [L3_TAP_WIDTH-1:0] l3_carry_o,
    output logic [   EXP_WIDTH-1:0] l3_exp_o
);

    logic [DP8_WIDTH-1:0] dp8_sum    [0:NUM_DP8-1];
    logic [DP8_WIDTH-1:0] dp8_carry  [0:NUM_DP8-1];

    logic [ L0_WIDTH-1:0] l0_sum     [ 0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_carry   [ 0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_sum_q   [ 0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_carry_q [ 0:NUM_L0-1];
    logic [ L1_WIDTH-1:0] l1_sum     [ 0:NUM_L1-1];
    logic [ L1_WIDTH-1:0] l1_carry   [ 0:NUM_L1-1];
    logic [ L2_WIDTH-1:0] l2_sum     [ 0:NUM_L2-1];
    logic [ L2_WIDTH-1:0] l2_carry   [ 0:NUM_L2-1];
    logic [ L0_WIDTH-1:0] l0_sum_g   [ 0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_carry_g [ 0:NUM_L0-1];
    logic [ L1_WIDTH-1:0] l1_sum_g   [ 0:NUM_L1-1];
    logic [ L1_WIDTH-1:0] l1_carry_g [ 0:NUM_L1-1];
    logic [ L2_WIDTH-1:0] l2_sum_g   [ 0:NUM_L2-1];
    logic [ L2_WIDTH-1:0] l2_carry_g [ 0:NUM_L2-1];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [ L3_WIDTH-1:0] l3_sum_w;
    logic [ L3_WIDTH-1:0] l3_carry_w;
    /* verilator lint_on UNUSEDSIGNAL */

    logic [EXP_WIDTH-1:0] exp_dp8    [0:NUM_DP8-1];
    logic [EXP_WIDTH-1:0] l0_exp     [ 0:NUM_L0-1];
    logic [EXP_WIDTH-1:0] l0_exp_q   [ 0:NUM_L0-1];
    logic [EXP_WIDTH-1:0] l1_exp     [ 0:NUM_L1-1];
    logic [EXP_WIDTH-1:0] l2_exp     [ 0:NUM_L2-1];

    genvar i, ln, n, j, k;

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
            logic [IN_WIDTH_A-1:0] a_lane [0:LANES-1];
            logic [IN_WIDTH_B-1:0] b_lane [0:LANES-1];
            for (ln = 0; ln < LANES; ln++) begin : gen_lane
                assign a_lane[ln] = a_dp8_i[i][ln*IN_WIDTH_A +: IN_WIDTH_A];
                assign b_lane[ln] = b_dp8_i[i][ln*IN_WIDTH_B +: IN_WIDTH_B];
            end
            dp_8_sqr dp_8_sqr_i (
                .a_i    (a_lane),
                .b_i    (b_lane),
                .sum_o  (dp8_sum[i]),
                .carry_o(dp8_carry[i])
            );
        end
    endgenerate

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_exp_dp8
            add_n #(.WIDTH(EXP_IN_WIDTH), .CARRY(1)) add_n_exp_i (
                .in_0_i({1'b0, exp_a_dp8_i[i]}), .in_1_i({1'b0, exp_b_dp8_i[i]}), .cin_i(1'b0),
                .out_o(exp_dp8[i][EXP_IN_WIDTH-1:0]), .cout_o(exp_dp8[i][EXP_IN_WIDTH])
            );
        end
    endgenerate

    logic [ P_WIDTH-1:0] p_sum   [0:NUM_DP8-1];
    logic [ P_WIDTH-1:0] p_carry [0:NUM_DP8-1];
    logic [ NUM_DP8-1:0] dp8_neg;

    always_comb begin
        dp8_neg = '0;
        for (int nn = 0; nn < NUM_NEG; nn++) begin
            dp8_neg[4*(nn/2) + (nn%2) + 2] = neg_i[nn];
        end
    end

    ext_inject_sqr_bfp #(.NUM_DP8(NUM_DP8), .DP8_WIDTH(DP8_WIDTH)) ext_inject_sqr_bfp_i (
        .pe_sum_i     (dp8_sum),
        .pe_carry_i   (dp8_carry),
        .alpha_sum_i  (alpha_sum_i),
        .alpha_carry_i(alpha_carry_i),
        .beta_sum_i   (beta_sum_i),
        .beta_carry_i (beta_carry_i),
        .const_i      (const_dp8_i),
        .zero_i       (zero_i),
        .neg_i        (dp8_neg),
        .sum_o        (p_sum),
        .carry_o      (p_carry)
    );

    generate
        for (n = 0; n < NUM_L0; n++) begin : gen_l0
            localparam int CX0 = 4*(n/2) + (n%2);
            localparam int CX1 = CX0 + 2;

            logic [ P_WIDTH-1:0] hi_in   [0:1];
            logic [ P_WIDTH-1:0] lo_in   [0:1];
            logic [ L0_WIDTH-1:0] hi_sh   [0:1];
            logic [ L0_WIDTH-1:0] lo_ext  [0:1];
            logic [ L0_WIDTH-1:0] zero_ch [0:1];
            logic [ L0_WIDTH-1:0] cpr_in  [0:3];

            assign hi_in[0] = p_sum[CX0];
            assign hi_in[1] = p_carry[CX0];
            assign lo_in[0] = p_sum[CX1];
            assign lo_in[1] = p_carry[CX1];

            shift_n #(.WIDTH(P_WIDTH), .SIZE(2), .SHIFT(SH0), .IS_SIGNED(1'b1)) shift_n_i (
                .in_i(hi_in), .sel_i(sel_shift_i[0]), .out_o(hi_sh)
            );
            ext_n #(.WIDTH(P_WIDTH), .SIZE(2), .EXT(SH0), .IS_SIGNED(1'b1)) ext_n_i (
                .in_i(lo_in), .out_o(lo_ext)
            );

            assign zero_ch[0] = '0;
            assign zero_ch[1] = '0;

            /* verilator lint_off PINCONNECTEMPTY */
            align_cell_bfp #(
                .WIDTH    (L0_WIDTH),
                .SIZE_0   (2),
                .SIZE_1   (2),
                .EXP_WIDTH(EXP_WIDTH),
                .IS_SIGNED(1'b1)
            ) align_cell_bfp_i (
                .in_0_i    (hi_sh),
                .exp_0_i   (exp_dp8[CX0]),
                .in_1_i    (lo_ext),
                .exp_1_i   (exp_dp8[CX1]),
                .chain_en_i(1'b0),
                .chain_0_i (zero_ch),
                .chain_1_i (zero_ch),
                .chain_0_o (),
                .chain_1_o (),
                .out_o     (cpr_in),
                .exp_o     (l0_exp[n])
            );
            /* verilator lint_on PINCONNECTEMPTY */

            cpr_w_n #(.IN_WIDTH(L0_WIDTH), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
                .in_i(cpr_in), .sum_o(l0_sum[n]), .carry_o(l0_carry[n])
            );
        end
    endgenerate

    reg_n #(.WIDTH(L0_WIDTH), .SIZE(NUM_L0)) reg_n_l0_sum_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(l0_sum), .q_o(l0_sum_q)
    );
    reg_n #(.WIDTH(L0_WIDTH), .SIZE(NUM_L0)) reg_n_l0_carry_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(l0_carry), .q_o(l0_carry_q)
    );
    reg_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_L0)) reg_n_l0_exp_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(l0_exp), .q_o(l0_exp_q)
    );

    generate
        for (n = 0; n < NUM_L0; n++) begin : gen_l0_iso
            assign l0_sum_g[n]   = l0_sum_q[n]   & {L0_WIDTH{en_level_i[0]}};
            assign l0_carry_g[n] = l0_carry_q[n] & {L0_WIDTH{en_level_i[0]}};
        end
        for (j = 0; j < NUM_L1; j++) begin : gen_l1_iso
            assign l1_sum_g[j]   = l1_sum[j]   & {L1_WIDTH{en_level_i[1]}};
            assign l1_carry_g[j] = l1_carry[j] & {L1_WIDTH{en_level_i[1]}};
        end
        for (k = 0; k < NUM_L2; k++) begin : gen_l2_iso
            assign l2_sum_g[k]   = l2_sum[k]   & {L2_WIDTH{en_level_i[2]}};
            assign l2_carry_g[k] = l2_carry[k] & {L2_WIDTH{en_level_i[2]}};
        end
    endgenerate

    generate
        for (j = 0; j < NUM_L1; j++) begin : gen_l1
            logic [       L0_WIDTH-1:0] hi_in  [0:1];
            logic [       L0_WIDTH-1:0] lo_in  [0:1];
            logic [(L0_WIDTH+SH1)-1:0]  hi_sh  [0:1];
            logic [(L0_WIDTH+SH1)-1:0]  lo_ext [0:1];
            logic [(L0_WIDTH+SH1)-1:0]  cpr_in [0:3];

            assign hi_in[0] = l0_sum_g[2*j];
            assign hi_in[1] = l0_carry_g[2*j];
            assign lo_in[0] = l0_sum_g[2*j+1];
            assign lo_in[1] = l0_carry_g[2*j+1];

            shift_n #(.WIDTH(L0_WIDTH), .SIZE(2), .SHIFT(SH1), .IS_SIGNED(1'b1)) shift_n_i (
                .in_i(hi_in), .sel_i(sel_shift_i[1]), .out_o(hi_sh)
            );
            ext_n #(.WIDTH(L0_WIDTH), .SIZE(2), .EXT(SH1), .IS_SIGNED(1'b1)) ext_n_i (
                .in_i(lo_in), .out_o(lo_ext)
            );

            assign cpr_in[0] = hi_sh[0];
            assign cpr_in[1] = hi_sh[1];
            assign cpr_in[2] = lo_ext[0];
            assign cpr_in[3] = lo_ext[1];

            cpr_w_n #(.IN_WIDTH(L0_WIDTH+SH1), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
                .in_i(cpr_in), .sum_o(l1_sum[j]), .carry_o(l1_carry[j])
            );

            logic [EXP_WIDTH-1:0] exp_in [0:1];
            logic                 exp_sign;

            assign exp_in[0] = l0_exp_q[2*j];
            assign exp_in[1] = l0_exp_q[2*j+1];

            /* verilator lint_off PINCONNECTEMPTY */
            sub_n_bfp #(.WIDTH(EXP_WIDTH)) sub_n_bfp_i (
                .in_0_i(l0_exp_q[2*j]), .in_1_i(l0_exp_q[2*j+1]), .abs_o(), .sign_o(exp_sign)
            );
            /* verilator lint_on PINCONNECTEMPTY */

            mux_n #(.WIDTH(EXP_WIDTH), .SIZE(2)) mux_n_exp_i (
                .in_i(exp_in), .sel_i(exp_sign), .out_o(l1_exp[j])
            );
        end
    endgenerate

    generate
        for (k = 0; k < NUM_L2; k++) begin : gen_l2
            logic [       L1_WIDTH-1:0] hi_in   [0:1];
            logic [       L1_WIDTH-1:0] lo_in   [0:1];
            logic [(L1_WIDTH+SH2)-1:0]  hi_sh   [0:1];
            logic [(L1_WIDTH+SH2)-1:0]  lo_ext  [0:1];
            logic [(L1_WIDTH+SH2)-1:0]  zero_ch [0:1];
            logic [(L1_WIDTH+SH2)-1:0]  cpr_in  [0:3];

            assign hi_in[0] = l1_sum_g[2*k];
            assign hi_in[1] = l1_carry_g[2*k];
            assign lo_in[0] = l1_sum_g[2*k+1];
            assign lo_in[1] = l1_carry_g[2*k+1];

            shift_n #(.WIDTH(L1_WIDTH), .SIZE(2), .SHIFT(SH2), .IS_SIGNED(1'b1)) shift_n_i (
                .in_i(hi_in), .sel_i(sel_shift_i[2]), .out_o(hi_sh)
            );
            ext_n #(.WIDTH(L1_WIDTH), .SIZE(2), .EXT(SH2), .IS_SIGNED(1'b1)) ext_n_i (
                .in_i(lo_in), .out_o(lo_ext)
            );

            assign zero_ch[0] = '0;
            assign zero_ch[1] = '0;

            /* verilator lint_off PINCONNECTEMPTY */
            align_cell_bfp #(
                .WIDTH    (L1_WIDTH+SH2),
                .SIZE_0   (2),
                .SIZE_1   (2),
                .EXP_WIDTH(EXP_WIDTH),
                .IS_SIGNED(1'b1)
            ) align_cell_bfp_i (
                .in_0_i    (hi_sh),
                .exp_0_i   (l1_exp[2*k]),
                .in_1_i    (lo_ext),
                .exp_1_i   (l1_exp[2*k+1]),
                .chain_en_i(1'b0),
                .chain_0_i (zero_ch),
                .chain_1_i (zero_ch),
                .chain_0_o (),
                .chain_1_o (),
                .out_o     (cpr_in),
                .exp_o     (l2_exp[k])
            );
            /* verilator lint_on PINCONNECTEMPTY */

            cpr_w_n #(.IN_WIDTH(L1_WIDTH+SH2), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
                .in_i(cpr_in), .sum_o(l2_sum[k]), .carry_o(l2_carry[k])
            );
        end
    endgenerate

    logic [L2_WIDTH-1:0] l3_hi_in   [0:1];
    logic [L2_WIDTH-1:0] l3_lo_in   [0:1];
    logic [L2_WIDTH-1:0] l3_zero_ch [0:1];
    logic [L2_WIDTH-1:0] l3_cpr_in  [0:3];

    assign l3_hi_in[0]   = l2_sum_g[0];
    assign l3_hi_in[1]   = l2_carry_g[0];
    assign l3_lo_in[0]   = l2_sum_g[1];
    assign l3_lo_in[1]   = l2_carry_g[1];
    assign l3_zero_ch[0] = '0;
    assign l3_zero_ch[1] = '0;

    /* verilator lint_off PINCONNECTEMPTY */
    align_cell_bfp #(
        .WIDTH    (L2_WIDTH),
        .SIZE_0   (2),
        .SIZE_1   (2),
        .EXP_WIDTH(EXP_WIDTH),
        .IS_SIGNED(1'b1)
    ) align_cell_bfp_l3_i (
        .in_0_i    (l3_hi_in),
        .exp_0_i   (l2_exp[0]),
        .in_1_i    (l3_lo_in),
        .exp_1_i   (l2_exp[1]),
        .chain_en_i(1'b0),
        .chain_0_i (l3_zero_ch),
        .chain_1_i (l3_zero_ch),
        .chain_0_o (),
        .chain_1_o (),
        .out_o     (l3_cpr_in),
        .exp_o     (l3_exp_o)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    cpr_w_n #(.IN_WIDTH(L2_WIDTH), .IN_SIZE(4), .EXT(L3_EXT), .IS_SIGNED(1'b1)) cpr_w_n_l3_i (
        .in_i(l3_cpr_in), .sum_o(l3_sum_w), .carry_o(l3_carry_w)
    );

    generate
        for (n = 0; n < NUM_L0; n++) begin : gen_l0_tap
            assign l0_sum_o[n]   = l0_sum_q[n][L0_TAP_WIDTH-1:0];
            assign l0_carry_o[n] = l0_carry_q[n][L0_TAP_WIDTH-1:0];
            assign l0_exp_o[n]   = l0_exp_q[n];
        end
        for (j = 0; j < NUM_L1; j++) begin : gen_l1_tap
            assign l1_sum_o[j]   = l1_sum[j][L1_TAP_WIDTH-1:0];
            assign l1_carry_o[j] = l1_carry[j][L1_TAP_WIDTH-1:0];
            assign l1_exp_o[j]   = l1_exp[j];
        end
        for (k = 0; k < NUM_L2; k++) begin : gen_l2_tap
            assign l2_sum_o[k]   = l2_sum[k][L2_TAP_WIDTH-1:0];
            assign l2_carry_o[k] = l2_carry[k][L2_TAP_WIDTH-1:0];
            assign l2_exp_o[k]   = l2_exp[k];
        end
    endgenerate

    assign l3_sum_o   = l3_sum_w[L3_TAP_WIDTH-1:0];
    assign l3_carry_o = l3_carry_w[L3_TAP_WIDTH-1:0];

endmodule
