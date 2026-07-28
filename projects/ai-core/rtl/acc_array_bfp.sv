// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   BFP-capable eight-lane accumulator - the acc_array variant with in-loop BFP
//   alignment. Same lane structure as acc_array (window/sign-extend the selected
//   tap, tap-level MUX, accumulate MUX, CPR 3:2, add_n, L->H adder-carry chain,
//   output register), plus one align_cell_bfp per lane inserted between the
//   accumulate MUX and the CPR: it brings the accumulator row and the tap
//   sum/carry pair to the common scale max(acc_exp, tap_exp) before the fold,
//   the smaller-exponent side arithmetic-right-shifted (truncating). With all
//   exponents equal every aligner is bit-transparent and the array behaves
//   exactly like acc_array (the pure-integer path); node and guard widths are
//   unchanged because an aligned addend is a right-shifted (smaller) version of
//   its integer worst case.
//
//   Exponent path: a per-lane OUT MUX EXP (sel_out_i) picks the tap's scale from
//   the pe_array_bfp tap exponents, mirroring the data window map (L0->[g],
//   L1->[g/2], L2->[0/1] on lanes 2,3,6,7, L3 on lanes 6,7; idle levels tied to
//   the minimum scale 0). A per-lane ACC MUX EXP (sel_acc_i) picks the seed
//   exponent acc_exp_i (external) or the lane's own registered scale (feedback),
//   matching the mantissa accumulate MUX. The aligner emits max(acc_exp,
//   tap_exp); an exponent register per lane (loaded every cycle, reset to the
//   minimum scale 0) holds it as the running accumulator scale and drives
//   pe_exp_o. The seed and the feedback share one format (20-bit mantissa,
//   40-bit split H/L over a lane pair, plus a 7-bit product-domain scale), so
//   the two accumulate MUXes just select between same-shape operands.
//
//   Lane fusion (prop_carry_i, pairs (0,1)(2,3)(4,5)(6,7), even=H/odd=L): the
//   pair's two aligners exchange shifted-out bits over an H->L fill chain - the
//   even (H) lane sign-fills and feeds its three raw rows (acc, tap sum, tap
//   carry), gated by prop_carry, into the odd (L) lane, whose fill comes from
//   that chain instead of sign replication. Fused they form one distributed
//   40-bit three-row shifter; ungated they align independently. This runs
//   alongside the existing L->H adder-carry chain: one control, two crossing
//   buses, opposite directions. A fused pair must receive equal exponents on
//   both lanes (guaranteed: both read the same tap node and, seeded
//   consistently, hold equal registered scales).
//
// Parameters:
//   None - fixed to the PE configuration (EXP_WIDTH = 7 holds e_A + e_B of two
//   6-bit format exponents).
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module acc_array_bfp #(
    localparam int NUM_LANE  = 8,
    localparam int PE_WIDTH  = 20,
    localparam int FUSE      = 40,
    localparam int CPR_WIDTH = PE_WIDTH + 2,
    localparam int CARRY     = 2,
    localparam int NUM_LVL   = 4,
    localparam int NUM_L0    = 8,
    localparam int NUM_L1    = 4,
    localparam int NUM_L2    = 2,
    localparam int L0_WIDTH  = 18,
    localparam int L1_WIDTH  = 29,
    localparam int L2_WIDTH  = 37,
    localparam int L3_WIDTH  = 38,
    localparam int SEL_WIDTH = 2,
    localparam int EXP_WIDTH = 7,
    localparam int ROWS      = 3
)(
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic [ L0_WIDTH-1:0] l0_sum_i   [0:NUM_L0-1],
    input  logic [ L0_WIDTH-1:0] l0_carry_i [0:NUM_L0-1],
    input  logic [ L1_WIDTH-1:0] l1_sum_i   [0:NUM_L1-1],
    input  logic [ L1_WIDTH-1:0] l1_carry_i [0:NUM_L1-1],
    input  logic [ L2_WIDTH-1:0] l2_sum_i   [0:NUM_L2-1],
    input  logic [ L2_WIDTH-1:0] l2_carry_i [0:NUM_L2-1],
    input  logic [ L3_WIDTH-1:0] l3_sum_i,
    input  logic [ L3_WIDTH-1:0] l3_carry_i,
    input  logic [EXP_WIDTH-1:0] l0_exp_i   [0:NUM_L0-1],
    input  logic [EXP_WIDTH-1:0] l1_exp_i   [0:NUM_L1-1],
    input  logic [EXP_WIDTH-1:0] l2_exp_i   [0:NUM_L2-1],
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

    logic [ PE_WIDTH-1:0] reg_q      [0:NUM_LANE-1];
    logic [EXP_WIDTH-1:0] reg_exp_q  [0:NUM_LANE-1];
    logic [    CARRY-1:0] lane_cin   [0:NUM_LANE-1];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [    CARRY-1:0] lane_carry [0:NUM_LANE-1];
    /* verilator lint_on UNUSEDSIGNAL */

    /* verilator lint_off UNUSEDSIGNAL */
    logic [PE_WIDTH-1:0] chain_row   [0:NUM_LANE-1][   0:ROWS-1];
    /* verilator lint_on UNUSEDSIGNAL */

    genvar g, l;

    generate
        for (g = 0; g < NUM_LANE; g++) begin : gen_lane

            /* verilator lint_off UNUSEDSIGNAL */
            assign w_sum[g][0] = PE_WIDTH'($signed(l0_sum_i[g]));
            assign w_car[g][0] = PE_WIDTH'($signed(l0_carry_i[g]));
            assign w_exp[g][0] = l0_exp_i[g];

            logic [FUSE-1:0] l1s, l1c;

            assign l1s = FUSE'($signed(l1_sum_i[g/2]));
            assign l1c = FUSE'($signed(l1_carry_i[g/2]));
            assign w_exp[g][1] = l1_exp_i[g/2];

            if (g % 2 == 0) begin : gen_l1_h
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
                if (g % 2 == 0) begin : gen_l2_h
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
                if (g % 2 == 0) begin : gen_l3_h
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
            logic [PE_WIDTH-1:0] acc_sel;

            assign accmux_in[0] = acc_i[g];
            assign accmux_in[1] = reg_q[g];

            mux_n #(.WIDTH(PE_WIDTH), .SIZE(2)) acc_mux_i (
                .in_i(accmux_in), .sel_i(sel_acc_i), .out_o(acc_sel)
            );

            logic [EXP_WIDTH-1:0] accmux_exp_in [0:1];
            logic [EXP_WIDTH-1:0] acc_exp_sel;

            assign accmux_exp_in[0] = acc_exp_i[g];
            assign accmux_exp_in[1] = reg_exp_q[g];

            mux_n #(.WIDTH(EXP_WIDTH), .SIZE(2)) acc_mux_exp_i (
                .in_i(accmux_exp_in), .sel_i(sel_acc_i), .out_o(acc_exp_sel)
            );

            logic [ PE_WIDTH-1:0] acc_row   [     0:0];
            logic [ PE_WIDTH-1:0] tap_pair  [     0:1];
            logic [ PE_WIDTH-1:0] align_out [0:ROWS-1];
            logic [EXP_WIDTH-1:0] align_exp;

            assign acc_row [0] = acc_sel;
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

            if (g % 2 == 0) begin : gen_align_h
                assign chain_en       = 1'b0;
                assign chain_acc_i[0] = '0;
                assign chain_tap_i[0] = '0;
                assign chain_tap_i[1] = '0;
            end else begin : gen_align_l
                logic [PE_WIDTH-1:0] chain_gated [0:ROWS-1];
                gate_n #(.WIDTH(PE_WIDTH), .SIZE(ROWS)) gate_n_chain_i (
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

            cpr_w_n #(.IN_WIDTH(PE_WIDTH), .IN_SIZE(3), .EXT(2), .IS_SIGNED(1'b0)) cpr_w_n_i (
                .in_i(cpr_in), .sum_o(cpr_sum), .carry_o(cpr_car)
            );

            logic [PE_WIDTH-1:0] rd [0:0];
            logic [PE_WIDTH-1:0] rq [0:0];

            add_n #(.WIDTH(PE_WIDTH), .CARRY(CARRY)) add_n_i (
                .in_0_i(cpr_sum), .in_1_i(cpr_car), .cin_i(lane_cin[g]),
                .out_o(rd[0]), .cout_o(lane_carry[g])
            );

            if (g % 2 == 0) begin : gen_carry
                logic [CARRY-1:0] cin_in  [0:0];
                logic [CARRY-1:0] cin_out [0:0];
                assign cin_in[0] = lane_carry[g+1];
                gate_n #(.WIDTH(CARRY), .SIZE(1)) gate_n_i (
                    .in_i(cin_in), .sel_i(~prop_carry_i), .out_o(cin_out)
                );
                assign lane_cin[g] = cin_out[0];
            end else begin : gen_no_carry
                assign lane_cin[g] = '0;
            end

            reg_n #(.WIDTH(PE_WIDTH), .SIZE(1)) reg_n_i (
                .clk_i(clk_i), .rst_ni(rst_ni), .d_i(rd), .q_o(rq)
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
