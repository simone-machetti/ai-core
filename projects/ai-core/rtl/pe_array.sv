// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   PE array. Instantiates the 16 DP8 cores and reduces their carry-save
//   outputs through a 4-level tree with programmable per-level shifts, exposing
//   a carry-save tap (sum + carry) at every level. Fixed to the PE.
//
//   Levels (each node is a CPR 4:2 merging two carry-save operands, the higher-
//   weight one left-shifted by the level amount when its sel_shift bit is set,
//   the other sign-extended to match):
//     - L0: 8 nodes, shift 8 (sel_shift[0]); combines a CROSSED DP8 pair
//           l0[2g]=dp8[4g]+dp8[4g+2], l0[2g+1]=dp8[4g+1]+dp8[4g+3]; the lower
//           DP8 index (higher weight) is the shifted operand. Registered.
//     - L1: 4 nodes, shift 4 (sel_shift[1]); l1[j]=l0[2j]+l0[2j+1].
//     - L2: 2 nodes, shift 8 (sel_shift[2]); l2[k]=l1[2k]+l1[2k+1].
//     - L3: 1 node,  no shift;               l3=l2[0]+l2[1].
//   The even child (l0[2j], l1[2k]) is the higher-weight (shifted) operand.
//
//   Widths: the 20-bit DP8 output already carries 4 guard bits above its 16-bit
//     value (sign-consistent), which is enough headroom for the whole tree, so
//     every compressor runs EXT = 0 and each node is just prev + shift:
//     node = 28 / 32 / 40 / 40 over L0..L3. Each tap is the output of a 4:2
//     compressor, so it exports the reading mode's value + 2 guard bits (the
//     compressor's own headroom): 18 / 29 / 37 / 38; the acc splits/sign-extends
//     them into its lanes. Everything is signed carry-save (IS_SIGNED = 1 on all
//     shifts/exts/CPRs).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module pe_array #(
    localparam int NUM_DP8      = 16,
    localparam int A_DP8_WIDTH  = 64,
    localparam int B_DP8_WIDTH  = 32,
    localparam int LANES        = 8,
    localparam int IN_WIDTH_A   = 8,
    localparam int IN_WIDTH_B   = 4,
    localparam int DP8_WIDTH    = 20,
    localparam int NUM_SHIFT    = 3,
    localparam int NUM_L0       = 8,
    localparam int NUM_L1       = 4,
    localparam int NUM_L2       = 2,
    localparam int SH0          = 8,
    localparam int SH1          = 4,
    localparam int SH2          = 8,
    localparam int L0_WIDTH     = DP8_WIDTH + SH0,
    localparam int L1_WIDTH     = L0_WIDTH + SH1,
    localparam int L2_WIDTH     = L1_WIDTH + SH2,
    localparam int L3_WIDTH     = L2_WIDTH,
    localparam int L0_TAP_WIDTH = 18,
    localparam int L1_TAP_WIDTH = 29,
    localparam int L2_TAP_WIDTH = 37,
    localparam int L3_TAP_WIDTH = 38
)(
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  logic [ A_DP8_WIDTH-1:0]  a_dp8_i       [0:NUM_DP8-1],
    input  logic [ B_DP8_WIDTH-1:0]  b_dp8_i       [0:NUM_DP8-1],
    input  logic                     is_signed_a_i [0:NUM_DP8-1],
    input  logic                     is_signed_b_i [0:NUM_DP8-1],
    input  logic [   NUM_SHIFT-1:0]  sel_shift_i,
    output logic [L0_TAP_WIDTH-1:0]  l0_sum_o      [0:NUM_L0-1],
    output logic [L0_TAP_WIDTH-1:0]  l0_carry_o    [0:NUM_L0-1],
    output logic [L1_TAP_WIDTH-1:0]  l1_sum_o      [0:NUM_L1-1],
    output logic [L1_TAP_WIDTH-1:0]  l1_carry_o    [0:NUM_L1-1],
    output logic [L2_TAP_WIDTH-1:0]  l2_sum_o      [0:NUM_L2-1],
    output logic [L2_TAP_WIDTH-1:0]  l2_carry_o    [0:NUM_L2-1],
    output logic [L3_TAP_WIDTH-1:0]  l3_sum_o,
    output logic [L3_TAP_WIDTH-1:0]  l3_carry_o
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
    /* verilator lint_off UNUSEDSIGNAL */
    logic [ L3_WIDTH-1:0] l3_sum_w;
    logic [ L3_WIDTH-1:0] l3_carry_w;
    /* verilator lint_on UNUSEDSIGNAL */

    genvar i, ln, n, j, k;

    generate
        for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
            logic [IN_WIDTH_A-1:0] a_lane [0:LANES-1];
            logic [IN_WIDTH_B-1:0] b_lane [0:LANES-1];
            for (ln = 0; ln < LANES; ln++) begin : gen_lane
                assign a_lane[ln] = a_dp8_i[i][ln*IN_WIDTH_A +: IN_WIDTH_A];
                assign b_lane[ln] = b_dp8_i[i][ln*IN_WIDTH_B +: IN_WIDTH_B];
            end
            dp_8 dp_8_i (
                .a_i          (a_lane),
                .b_i          (b_lane),
                .is_signed_a_i(is_signed_a_i[i]),
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
            logic [       DP8_WIDTH-1:0] hi_in  [0:1];
            logic [       DP8_WIDTH-1:0] lo_in  [0:1];
            logic [(DP8_WIDTH+SH0)-1:0]  hi_sh  [0:1];
            logic [(DP8_WIDTH+SH0)-1:0]  lo_ext [0:1];
            logic [(DP8_WIDTH+SH0)-1:0]  cpr_in [0:3];

            assign hi_in[0] = dp8_sum[CX0];
            assign hi_in[1] = dp8_carry[CX0];
            assign lo_in[0] = dp8_sum[CX1];
            assign lo_in[1] = dp8_carry[CX1];

            shift_n #(.WIDTH(DP8_WIDTH), .SIZE(2), .SHIFT(SH0), .IS_SIGNED(1'b1)) shift_n_i (
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
        for (j = 0; j < NUM_L1; j++) begin : gen_l1
            logic [       L0_WIDTH-1:0] hi_in  [0:1];
            logic [       L0_WIDTH-1:0] lo_in  [0:1];
            logic [(L0_WIDTH+SH1)-1:0]  hi_sh  [0:1];
            logic [(L0_WIDTH+SH1)-1:0]  lo_ext [0:1];
            logic [(L0_WIDTH+SH1)-1:0]  cpr_in [0:3];

            assign hi_in[0] = l0_sum_q[2*j];
            assign hi_in[1] = l0_carry_q[2*j];
            assign lo_in[0] = l0_sum_q[2*j+1];
            assign lo_in[1] = l0_carry_q[2*j+1];

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
            logic [       L1_WIDTH-1:0] hi_in  [0:1];
            logic [       L1_WIDTH-1:0] lo_in  [0:1];
            logic [(L1_WIDTH+SH2)-1:0]  hi_sh  [0:1];
            logic [(L1_WIDTH+SH2)-1:0]  lo_ext [0:1];
            logic [(L1_WIDTH+SH2)-1:0]  cpr_in [0:3];

            assign hi_in[0] = l1_sum[2*k];
            assign hi_in[1] = l1_carry[2*k];
            assign lo_in[0] = l1_sum[2*k+1];
            assign lo_in[1] = l1_carry[2*k+1];

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
    assign l3_cpr_in[0] = l2_sum[0];
    assign l3_cpr_in[1] = l2_carry[0];
    assign l3_cpr_in[2] = l2_sum[1];
    assign l3_cpr_in[3] = l2_carry[1];

    cpr_w_n #(.IN_WIDTH(L2_WIDTH), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_l3_i (
        .in_i(l3_cpr_in), .sum_o(l3_sum_w), .carry_o(l3_carry_w)
    );

    generate
        for (n = 0; n < NUM_L0; n++) begin : gen_l0_tap
            assign l0_sum_o[n]   = l0_sum_q[n][L0_TAP_WIDTH-1:0];
            assign l0_carry_o[n] = l0_carry_q[n][L0_TAP_WIDTH-1:0];
        end
        for (j = 0; j < NUM_L1; j++) begin : gen_l1_tap
            assign l1_sum_o[j]   = l1_sum[j][L1_TAP_WIDTH-1:0];
            assign l1_carry_o[j] = l1_carry[j][L1_TAP_WIDTH-1:0];
        end
        for (k = 0; k < NUM_L2; k++) begin : gen_l2_tap
            assign l2_sum_o[k]   = l2_sum[k][L2_TAP_WIDTH-1:0];
            assign l2_carry_o[k] = l2_carry[k][L2_TAP_WIDTH-1:0];
        end
    endgenerate

    assign l3_sum_o   = l3_sum_w[L3_TAP_WIDTH-1:0];
    assign l3_carry_o = l3_carry_w[L3_TAP_WIDTH-1:0];

endmodule
