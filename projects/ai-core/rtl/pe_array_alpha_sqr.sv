// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Alpha array, square variant - the per-row A-only correction generator. It
//   is pe_array_sqr with the B operand removed and the 16 DP8 cores swapped to
//   dp_8_alpha_sqr: identical 4-level crossed CPR-4:2 tree, complex-mode block
//   negate, widths and taps. It reduces the 16 per-DP8 alpha square-sums
//   ALPHA_DP8 (each = 2^4*sum (AH-8*bu)^2 + sum (AL-8*bu)^2, the removed B
//   operand's -8 injected in dp_8_alpha_sqr) through the same L(.) as the PE, so
//   the downstream reconstruction Result = 1/2(PE - alpha - beta + C) is exact.
//
//   Output taps are one's-complemented: the module emits -alpha (each tap pair
//   resolves to -alpha_tap - 2) so the accumulator ADDS it instead of
//   subtracting. Done once here (shared by the row's PEs) rather than in every
//   accumulator; the deferred -2 per operand is the +4 folded into const_sqr.
//
//   Everything below the DP8 leaves is identical to pe_array_sqr: the crossed
//   L0 pairing, the 6 comp_n block-negates on L0 nodes 0..5 (alpha's blocks
//   carry the *same* neg as the PE - a negated block resolves to -ALPHA_DP8-2),
//   the unsigned L0 hi shift, the single L0 register, and the tap slicing. Node
//   = 18 / 26 / 30 / 38 / 39 over DP8..L3; taps 19 / 30 / 38 / 39. Per row of
//   the grid, fanned into every PE in that row. See pe_array_sqr for the tree.
//   Operand isolation: en_level_i AND-masks the branch from each level into the
//   next, so nothing below the tap the mode reads toggles. en_level_i[0] gates
//   L0 into L1, [1] gates L1 into L2, [2] gates L2 into L3; the taps themselves
//   are driven from the ungated signals, so the level being read is unaffected.
//   Nothing is gated below L3 - there is nothing downstream of it.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_array_alpha_sqr #(
    localparam int NUM_DP8      = 16,
    localparam int A_DP8_WIDTH  = 64,
    localparam int LANES        = 8,
    localparam int IN_WIDTH_A   = 8,
    localparam int DP8_WIDTH    = 18,
    localparam int NUM_SHIFT    = 3,
    localparam int NUM_LEVEL    = 3,
    localparam int NUM_L0       = 8,
    localparam int NUM_L1       = 4,
    localparam int NUM_L2       = 2,
    localparam int NUM_NEG      = 6,
    localparam int SH0          = 8,
    localparam int SH1          = 4,
    localparam int SH2          = 8,
    localparam int L0_WIDTH     = DP8_WIDTH + SH0,
    localparam int L1_WIDTH     = L0_WIDTH + SH1,
    localparam int L2_WIDTH     = L1_WIDTH + SH2,
    localparam int L3_EXT       = 1,
    localparam int L3_WIDTH     = L2_WIDTH + L3_EXT,
    localparam int L0_TAP_WIDTH = 19,
    localparam int L1_TAP_WIDTH = 30,
    localparam int L2_TAP_WIDTH = 38,
    localparam int L3_TAP_WIDTH = 39
)(
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic [ A_DP8_WIDTH-1:0] a_dp8_i       [0:NUM_DP8-1],
    input  logic                    is_signed_b_i [0:NUM_DP8-1],
    input  logic [     NUM_NEG-1:0] neg_i,
    input  logic [   NUM_SHIFT-1:0] sel_shift_i,
    input  logic [   NUM_LEVEL-1:0] en_level_i,
    output logic [L0_TAP_WIDTH-1:0] l0_sum_o   [0:NUM_L0-1],
    output logic [L0_TAP_WIDTH-1:0] l0_carry_o [0:NUM_L0-1],
    output logic [L1_TAP_WIDTH-1:0] l1_sum_o   [0:NUM_L1-1],
    output logic [L1_TAP_WIDTH-1:0] l1_carry_o [0:NUM_L1-1],
    output logic [L2_TAP_WIDTH-1:0] l2_sum_o   [0:NUM_L2-1],
    output logic [L2_TAP_WIDTH-1:0] l2_carry_o [0:NUM_L2-1],
    output logic [L3_TAP_WIDTH-1:0] l3_sum_o,
    output logic [L3_TAP_WIDTH-1:0] l3_carry_o
);

    logic [DP8_WIDTH-1:0] dp8_sum   [0:NUM_DP8-1];
    logic [DP8_WIDTH-1:0] dp8_carry [0:NUM_DP8-1];

    logic [ L0_WIDTH-1:0] l0_sum     [0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_carry   [0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_sum_q   [0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_carry_q [0:NUM_L0-1];
    logic [ L1_WIDTH-1:0] l1_sum     [0:NUM_L1-1];
    logic [ L1_WIDTH-1:0] l1_carry   [0:NUM_L1-1];
    logic [ L2_WIDTH-1:0] l2_sum     [0:NUM_L2-1];
    logic [ L2_WIDTH-1:0] l2_carry   [0:NUM_L2-1];
    logic [ L0_WIDTH-1:0] l0_sum_g   [0:NUM_L0-1];
    logic [ L0_WIDTH-1:0] l0_carry_g [0:NUM_L0-1];
    logic [ L1_WIDTH-1:0] l1_sum_g   [0:NUM_L1-1];
    logic [ L1_WIDTH-1:0] l1_carry_g [0:NUM_L1-1];
    logic [ L2_WIDTH-1:0] l2_sum_g   [0:NUM_L2-1];
    logic [ L2_WIDTH-1:0] l2_carry_g [0:NUM_L2-1];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [ L3_WIDTH-1:0] l3_sum_w;
    logic [ L3_WIDTH-1:0] l3_carry_w;
    /* verilator lint_on UNUSEDSIGNAL */

    genvar i, ln, n, j, k;

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
            logic [IN_WIDTH_A-1:0] a_lane [0:LANES-1];
            for (ln = 0; ln < LANES; ln++) begin : gen_lane
                assign a_lane[ln] = a_dp8_i[i][ln*IN_WIDTH_A +: IN_WIDTH_A];
            end
            dp_8_alpha_sqr dp_8_alpha_sqr_i (
                .a_i          (a_lane),
                .is_signed_b_i(is_signed_b_i[i]),
                .sum_o        (dp8_sum[i]),
                .carry_o      (dp8_carry[i])
            );
        end
    endgenerate

    generate
        for (n = 0; n < NUM_L0; n++) begin : gen_l0
            localparam int CX0 = 4*(n/2) + (n%2);
            localparam int CX1 = CX0 + 2;
            logic [      DP8_WIDTH-1:0] hi_in  [0:1];
            logic [      DP8_WIDTH-1:0] lo_raw [0:1];
            logic [      DP8_WIDTH-1:0] lo_in  [0:1];
            logic [(DP8_WIDTH+SH0)-1:0] hi_sh  [0:1];
            logic [(DP8_WIDTH+SH0)-1:0] lo_ext [0:1];
            logic [(DP8_WIDTH+SH0)-1:0] cpr_in [0:3];

            assign hi_in[0]  = dp8_sum[CX0];
            assign hi_in[1]  = dp8_carry[CX0];
            assign lo_raw[0] = dp8_sum[CX1];
            assign lo_raw[1] = dp8_carry[CX1];

            if (n < NUM_NEG) begin : gen_comp
                comp_n #(.WIDTH(DP8_WIDTH), .SIZE(2)) comp_n_i (
                    .in_i(lo_raw), .neg_i(neg_i[n]), .out_o(lo_in)
                );
            end else begin : gen_nocomp
                assign lo_in[0] = lo_raw[0];
                assign lo_in[1] = lo_raw[1];
            end

            shift_n #(.WIDTH(DP8_WIDTH), .SIZE(2), .SHIFT(SH0), .IS_SIGNED(1'b0)) shift_n_i (
                .in_i(hi_in), .sel_i(sel_shift_i[0]), .out_o(hi_sh)
            );
            ext_n #(.WIDTH(DP8_WIDTH), .SIZE(2), .EXT(SH0), .IS_SIGNED(1'b1)) ext_n_i (
                .in_i(lo_in), .out_o(lo_ext)
            );

            assign cpr_in[0] = hi_sh[0];
            assign cpr_in[1] = hi_sh[1];
            assign cpr_in[2] = lo_ext[0];
            assign cpr_in[3] = lo_ext[1];

            cpr_w_n #(.IN_WIDTH(DP8_WIDTH+SH0), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
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
            logic [      L0_WIDTH-1:0] hi_in  [0:1];
            logic [      L0_WIDTH-1:0] lo_in  [0:1];
            logic [(L0_WIDTH+SH1)-1:0] hi_sh  [0:1];
            logic [(L0_WIDTH+SH1)-1:0] lo_ext [0:1];
            logic [(L0_WIDTH+SH1)-1:0] cpr_in [0:3];

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
        end
    endgenerate

    generate
        for (k = 0; k < NUM_L2; k++) begin : gen_l2
            logic [      L1_WIDTH-1:0] hi_in  [0:1];
            logic [      L1_WIDTH-1:0] lo_in  [0:1];
            logic [(L1_WIDTH+SH2)-1:0] hi_sh  [0:1];
            logic [(L1_WIDTH+SH2)-1:0] lo_ext [0:1];
            logic [(L1_WIDTH+SH2)-1:0] cpr_in [0:3];

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

            assign cpr_in[0] = hi_sh[0];
            assign cpr_in[1] = hi_sh[1];
            assign cpr_in[2] = lo_ext[0];
            assign cpr_in[3] = lo_ext[1];

            cpr_w_n #(.IN_WIDTH(L1_WIDTH+SH2), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
                .in_i(cpr_in), .sum_o(l2_sum[k]), .carry_o(l2_carry[k])
            );
        end
    endgenerate

    logic [L2_WIDTH-1:0] l3_cpr_in [0:3];
    assign l3_cpr_in[0] = l2_sum_g[0];
    assign l3_cpr_in[1] = l2_carry_g[0];
    assign l3_cpr_in[2] = l2_sum_g[1];
    assign l3_cpr_in[3] = l2_carry_g[1];

    cpr_w_n #(.IN_WIDTH(L2_WIDTH), .IN_SIZE(4), .EXT(L3_EXT), .IS_SIGNED(1'b1)) cpr_w_n_l3_i (
        .in_i(l3_cpr_in), .sum_o(l3_sum_w), .carry_o(l3_carry_w)
    );

    generate
        for (n = 0; n < NUM_L0; n++) begin : gen_l0_tap
            assign l0_sum_o[n]   = ~l0_sum_q[n][L0_TAP_WIDTH-1:0];
            assign l0_carry_o[n] = ~l0_carry_q[n][L0_TAP_WIDTH-1:0];
        end
        for (j = 0; j < NUM_L1; j++) begin : gen_l1_tap
            assign l1_sum_o[j]   = ~l1_sum[j][L1_TAP_WIDTH-1:0];
            assign l1_carry_o[j] = ~l1_carry[j][L1_TAP_WIDTH-1:0];
        end
        for (k = 0; k < NUM_L2; k++) begin : gen_l2_tap
            assign l2_sum_o[k]   = ~l2_sum[k][L2_TAP_WIDTH-1:0];
            assign l2_carry_o[k] = ~l2_carry[k][L2_TAP_WIDTH-1:0];
        end
    endgenerate

    assign l3_sum_o   = ~l3_sum_w[L3_TAP_WIDTH-1:0];
    assign l3_carry_o = ~l3_carry_w[L3_TAP_WIDTH-1:0];

endmodule
