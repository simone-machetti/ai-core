// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Eight-lane accumulator, square + BFP variant - the final stage of the
//   square-BFP PE. It is acc_array_bfp (per-lane align_cell_bfp bringing the acc
//   row and the tap sum/carry pair to max(acc_exp, tap_exp), running-max exponent
//   register, seed = feedback format, lane-fusion align chain, L->H adder carry)
//   plus the square's /2, borrowed verbatim from acc_array_sqr:
//     - acc_x2: a LEFT shift <<1 on the acc-mux output so the accumulated term
//       enters the fold at 2x (fused pair: the low lane's shifted-out MSB fills
//       the high lane's LSB). Keeps acc_i / pe_out in native units.
//     - half:   an arithmetic >>1 on the resolved sum before the register - the
//       /2 (fused pair: the high lane's shifted-out LSB fills the low lane's MSB).
//   Because the tree already delivers 2*P as ONE tap pair, the combine
//   PE - alpha - beta + C is not done here: there is a single tap set (no
//   alpha/beta taps) and no C / c_neg ports (C is injected per-DP8 upstream at
//   L0). The register holds P + acc at its running BFP scale;
//   1/2*(2*acc + 2*P) = acc + P, exact when the resolved sum is even (equal
//   exponents), so with all exponents equal the array is bit-identical to
//   acc_array_sqr fed the same result.
//
//   Widths: tap inputs are the pe_array_sqr_bfp taps 19/30/38/39 (baseline-BFP
//   + 1, they carry 2*P). CARRY = 3 (the <<1 adds a bit of inter-lane carry over
//   acc_array_bfp's 2). Node/guard widths are otherwise acc_array_bfp's.
//
// Parameters:
//   None - fixed to the PE configuration (EXP_WIDTH = 7 holds e_A + e_B).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module acc_array_sqr_bfp #(
    localparam int NUM_LANE  = 8,
    localparam int PE_WIDTH  = 20,
    localparam int FUSE      = 40,
    localparam int EXT       = 3,
    localparam int CPR_WIDTH = PE_WIDTH + EXT,
    localparam int CARRY     = 3,
    localparam int NUM_LVL   = 4,
    localparam int NUM_L0    = 8,
    localparam int NUM_L1    = 4,
    localparam int NUM_L2    = 2,
    localparam int L0_WIDTH  = 19,
    localparam int L1_WIDTH  = 30,
    localparam int L2_WIDTH  = 38,
    localparam int L3_WIDTH  = 39,
    localparam int SEL_WIDTH = 2,
    localparam int EXP_WIDTH = 7,
    localparam int ROWS      = 3
)(
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic [ L0_WIDTH-1:0] l0_sum_i   [  0:NUM_L0-1],
    input  logic [ L0_WIDTH-1:0] l0_carry_i [  0:NUM_L0-1],
    input  logic [ L1_WIDTH-1:0] l1_sum_i   [  0:NUM_L1-1],
    input  logic [ L1_WIDTH-1:0] l1_carry_i [  0:NUM_L1-1],
    input  logic [ L2_WIDTH-1:0] l2_sum_i   [  0:NUM_L2-1],
    input  logic [ L2_WIDTH-1:0] l2_carry_i [  0:NUM_L2-1],
    input  logic [ L3_WIDTH-1:0] l3_sum_i,
    input  logic [ L3_WIDTH-1:0] l3_carry_i,
    input  logic [EXP_WIDTH-1:0] l0_exp_i   [  0:NUM_L0-1],
    input  logic [EXP_WIDTH-1:0] l1_exp_i   [  0:NUM_L1-1],
    input  logic [EXP_WIDTH-1:0] l2_exp_i   [  0:NUM_L2-1],
    input  logic [EXP_WIDTH-1:0] l3_exp_i,
    input  logic [ PE_WIDTH-1:0] acc_i      [0:NUM_LANE-1],
    input  logic [EXP_WIDTH-1:0] acc_exp_i  [0:NUM_LANE-1],
    input  logic [SEL_WIDTH-1:0] sel_out_i,
    input  logic                 sel_acc_i,
    input  logic                 prop_carry_i,
    output logic [ PE_WIDTH-1:0] pe_out_o   [0:NUM_LANE-1],
    output logic [EXP_WIDTH-1:0] pe_exp_o   [0:NUM_LANE-1]
);

    logic [ PE_WIDTH-1:0] w_sum      [0:NUM_LANE-1][0:NUM_LVL-1];
    logic [ PE_WIDTH-1:0] w_car      [0:NUM_LANE-1][0:NUM_LVL-1];
    logic [EXP_WIDTH-1:0] w_exp      [0:NUM_LANE-1][0:NUM_LVL-1];

    logic [ PE_WIDTH-1:0] acc_sel    [0:NUM_LANE-1];
    logic [ PE_WIDTH-1:0] acc_x2     [0:NUM_LANE-1];
    logic [ PE_WIDTH-1:0] rd         [0:NUM_LANE-1];
    logic [ PE_WIDTH-1:0] half       [0:NUM_LANE-1];
    logic [ PE_WIDTH-1:0] reg_q      [0:NUM_LANE-1];
    logic [EXP_WIDTH-1:0] reg_exp_q  [0:NUM_LANE-1];
    logic [    CARRY-1:0] lane_cin   [0:NUM_LANE-1];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [    CARRY-1:0] lane_carry [0:NUM_LANE-1];
    logic [ PE_WIDTH-1:0] chain_row  [0:NUM_LANE-1][   0:ROWS-1];
    /* verilator lint_on UNUSEDSIGNAL */

    logic fused;
    assign fused = |sel_out_i;

    genvar g, l;

    generate
        for (g = 0; g < NUM_LANE; g++) begin : gen_lane

            localparam bit IS_EVEN = (g % 2 == 0);

            /* verilator lint_off UNUSEDSIGNAL */
            assign w_sum[g][0] = PE_WIDTH'($signed(l0_sum_i[g]));
            assign w_car[g][0] = PE_WIDTH'($signed(l0_carry_i[g]));
            assign w_exp[g][0] = l0_exp_i[g];

            logic [FUSE-1:0] l1s, l1c;

            assign l1s = FUSE'($signed(l1_sum_i[g/2]));
            assign l1c = FUSE'($signed(l1_carry_i[g/2]));
            assign w_exp[g][1] = l1_exp_i[g/2];

            if (IS_EVEN) begin : gen_l1_h
                assign w_sum[g][1] = l1s[FUSE-1:PE_WIDTH];
                assign w_car[g][1] = l1c[FUSE-1:PE_WIDTH];
            end else begin : gen_l1_l
                assign w_sum[g][1] = l1s[PE_WIDTH-1:0];
                assign w_car[g][1] = l1c[PE_WIDTH-1:0];
            end

            if (g == 2 || g == 3 || g == 6 || g == 7) begin : gen_l2
                localparam int N2 = (g <= 3) ? 0 : 1;
                logic [FUSE-1:0] l2s, l2c;
                assign l2s = FUSE'($signed(l2_sum_i[N2]));
                assign l2c = FUSE'($signed(l2_carry_i[N2]));
                assign w_exp[g][2] = l2_exp_i[N2];
                if (IS_EVEN) begin : gen_l2_h
                    assign w_sum[g][2] = l2s[FUSE-1:PE_WIDTH];
                    assign w_car[g][2] = l2c[FUSE-1:PE_WIDTH];
                end else begin : gen_l2_l
                    assign w_sum[g][2] = l2s[PE_WIDTH-1:0];
                    assign w_car[g][2] = l2c[PE_WIDTH-1:0];
                end
            end else begin : gen_no_l2
                assign w_sum[g][2] = '0;
                assign w_car[g][2] = '0;
                assign w_exp[g][2] = '0;
            end

            if (g == 6 || g == 7) begin : gen_l3
                logic [FUSE-1:0] l3s, l3c;
                assign l3s = FUSE'($signed(l3_sum_i));
                assign l3c = FUSE'($signed(l3_carry_i));
                assign w_exp[g][3] = l3_exp_i;
                if (IS_EVEN) begin : gen_l3_h
                    assign w_sum[g][3] = l3s[FUSE-1:PE_WIDTH];
                    assign w_car[g][3] = l3c[FUSE-1:PE_WIDTH];
                end else begin : gen_l3_l
                    assign w_sum[g][3] = l3s[PE_WIDTH-1:0];
                    assign w_car[g][3] = l3c[PE_WIDTH-1:0];
                end
            end else begin : gen_no_l3
                assign w_sum[g][3] = '0;
                assign w_car[g][3] = '0;
                assign w_exp[g][3] = '0;
            end
            /* verilator lint_on UNUSEDSIGNAL */

            logic [2*PE_WIDTH-1:0] tapmux_in [0:NUM_LVL-1];
            logic [2*PE_WIDTH-1:0] tapmux_out;
            logic [    PE_WIDTH-1:0] tap_sum, tap_car;
            logic [   EXP_WIDTH-1:0] tap_exp;

            for (l = 0; l < NUM_LVL; l++) begin : gen_pack
                assign tapmux_in[l] = {w_car[g][l], w_sum[g][l]};
            end

            mux_n #(.WIDTH(2*PE_WIDTH), .SIZE(NUM_LVL)) tap_mux_i (
                .in_i(tapmux_in), .sel_i(sel_out_i), .out_o(tapmux_out)
            );

            mux_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_LVL)) tap_mux_exp_i (
                .in_i(w_exp[g]), .sel_i(sel_out_i), .out_o(tap_exp)
            );

            assign tap_sum = tapmux_out[PE_WIDTH-1:0];
            assign tap_car = tapmux_out[2*PE_WIDTH-1:PE_WIDTH];

            logic [PE_WIDTH-1:0] accmux_in [0:1];

            assign accmux_in[0] = acc_i[g];
            assign accmux_in[1] = reg_q[g];

            mux_n #(.WIDTH(PE_WIDTH), .SIZE(2)) acc_mux_i (
                .in_i(accmux_in), .sel_i(sel_acc_i), .out_o(acc_sel[g])
            );

            logic [EXP_WIDTH-1:0] accmux_exp_in [0:1];
            logic [EXP_WIDTH-1:0] acc_exp_sel;

            assign accmux_exp_in[0] = acc_exp_i[g];
            assign accmux_exp_in[1] = reg_exp_q[g];

            mux_n #(.WIDTH(EXP_WIDTH), .SIZE(2)) acc_mux_exp_i (
                .in_i(accmux_exp_in), .sel_i(sel_acc_i), .out_o(acc_exp_sel)
            );

            if (IS_EVEN) begin : gen_accx2_h
                logic [0:0] msb_in  [0:0];
                logic [0:0] msb_out [0:0];
                assign msb_in[0] = acc_sel[g+1][PE_WIDTH-1];
                gate_n #(.WIDTH(1), .SIZE(1)) gate_n_mul_2_i (
                    .in_i(msb_in), .sel_i(~fused), .out_o(msb_out)
                );
                assign acc_x2[g] = {acc_sel[g][PE_WIDTH-2:0], msb_out[0]};
            end else begin : gen_accx2_l
                assign acc_x2[g] = {acc_sel[g][PE_WIDTH-2:0], 1'b0};
            end

            logic [ PE_WIDTH-1:0] acc_row   [     0:0];
            logic [ PE_WIDTH-1:0] tap_pair  [     0:1];
            logic [ PE_WIDTH-1:0] align_out [0:ROWS-1];
            logic [EXP_WIDTH-1:0] align_exp;

            assign acc_row [0] = acc_x2[g];
            assign tap_pair[0] = tap_sum;
            assign tap_pair[1] = tap_car;

            logic [PE_WIDTH-1:0] chain_acc_i [0:0];
            logic [PE_WIDTH-1:0] chain_tap_i [0:1];
            logic [PE_WIDTH-1:0] chain_acc_o [0:0];
            logic [PE_WIDTH-1:0] chain_tap_o [0:1];
            logic                chain_en;

            assign chain_row[g][0] = chain_acc_o[0];
            assign chain_row[g][1] = chain_tap_o[0];
            assign chain_row[g][2] = chain_tap_o[1];

            if (IS_EVEN) begin : gen_align_h
                assign chain_en       = 1'b0;
                assign chain_acc_i[0] = '0;
                assign chain_tap_i[0] = '0;
                assign chain_tap_i[1] = '0;
            end else begin : gen_align_l
                logic [PE_WIDTH-1:0] chain_gated [0:ROWS-1];
                gate_n #(.WIDTH(PE_WIDTH), .SIZE(ROWS)) gate_n_align_i (
                    .in_i(chain_row[g-1]), .sel_i(~prop_carry_i), .out_o(chain_gated)
                );
                assign chain_en       = prop_carry_i;
                assign chain_acc_i[0] = chain_gated[0];
                assign chain_tap_i[0] = chain_gated[1];
                assign chain_tap_i[1] = chain_gated[2];
            end

            /* verilator lint_off PINCONNECTEMPTY */
            align_cell_bfp #(
                .WIDTH    (PE_WIDTH),
                .SIZE_0   (1),
                .SIZE_1   (2),
                .EXP_WIDTH(EXP_WIDTH),
                .IS_SIGNED(1'b1)
            ) align_cell_bfp_i (
                .in_0_i    (acc_row),
                .exp_0_i   (acc_exp_sel),
                .in_1_i    (tap_pair),
                .exp_1_i   (tap_exp),
                .chain_en_i(chain_en),
                .chain_0_i (chain_acc_i),
                .chain_1_i (chain_tap_i),
                .chain_0_o (chain_acc_o),
                .chain_1_o (chain_tap_o),
                .out_o     (align_out),
                .exp_o     (align_exp)
            );
            /* verilator lint_on PINCONNECTEMPTY */

            logic [ PE_WIDTH-1:0] cpr_in [0:2];
            logic [CPR_WIDTH-1:0] cpr_sum, cpr_car;

            assign cpr_in[0] = align_out[0];
            assign cpr_in[1] = align_out[1];
            assign cpr_in[2] = align_out[2];

            cpr_w_n #(.IN_WIDTH(PE_WIDTH), .IN_SIZE(3), .EXT(EXT), .IS_SIGNED(1'b0)) cpr_w_n_i (
                .in_i(cpr_in), .sum_o(cpr_sum), .carry_o(cpr_car)
            );

            logic [PE_WIDTH-1:0] rd_l [0:0];

            add_n #(.WIDTH(PE_WIDTH), .CARRY(CARRY)) add_n_i (
                .in_0_i(cpr_sum), .in_1_i(cpr_car), .cin_i(lane_cin[g]),
                .out_o(rd_l[0]), .cout_o(lane_carry[g])
            );

            assign rd[g] = rd_l[0];

            if (IS_EVEN) begin : gen_carry
                logic [CARRY-1:0] cin_in  [0:0];
                logic [CARRY-1:0] cin_out [0:0];
                assign cin_in[0] = lane_carry[g+1];
                gate_n #(.WIDTH(CARRY), .SIZE(1)) gate_n_add_i (
                    .in_i(cin_in), .sel_i(~prop_carry_i), .out_o(cin_out)
                );
                assign lane_cin[g] = cin_out[0];
            end else begin : gen_no_carry
                assign lane_cin[g] = '0;
            end

            logic [PE_WIDTH-1:0] half_l [0:0];

            if (IS_EVEN) begin : gen_half_h
                assign half[g] = {rd[g][PE_WIDTH-1], rd[g][PE_WIDTH-1:1]};
            end else begin : gen_half_l
                assign half[g] = {(fused ? rd[g-1][0] : rd[g][PE_WIDTH-1]),
                                  rd[g][PE_WIDTH-1:1]};
            end

            assign half_l[0] = half[g];

            logic [PE_WIDTH-1:0] rq [0:0];

            reg_n #(.WIDTH(PE_WIDTH), .SIZE(1)) reg_n_i (
                .clk_i(clk_i), .rst_ni(rst_ni), .d_i(half_l), .q_o(rq)
            );

            logic [EXP_WIDTH-1:0] red [0:0];
            logic [EXP_WIDTH-1:0] req [0:0];

            assign red[0] = align_exp;

            reg_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) reg_n_exp_i (
                .clk_i(clk_i), .rst_ni(rst_ni), .d_i(red), .q_o(req)
            );

            assign reg_q[g]     = rq[0];
            assign reg_exp_q[g] = req[0];
        end
    endgenerate

    assign pe_out_o = reg_q;
    assign pe_exp_o = reg_exp_q;

endmodule
