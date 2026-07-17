// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Eight-lane accumulator, square variant - the final stage of the square PE.
//   Same lane / lane-pair-fusion shape as acc_array (even lane = high half
//   [39:20], odd = low [19:0]; L0 single-lane), but it resolves the square
//   reconstruction out = 1/2(PE - alpha - beta + C) as a pure carry-save ADD -
//   no subtractor, no carry-in injection - because the alpha/beta generators
//   already emit -alpha/-beta and const_sqr folds every +1/+2 deferral into C.
//
//   Per lane:
//     - window + tap-level MUX (sel_out_i) three carry-save operands: PE, -alpha
//       and -beta -> 6 rows (a sum/carry pair each), each 20-bit.
//     - acc MUX (sel_acc_i): external seed acc_i or the register feedback, then a
//       LEFT shift <<1 on its output so the accumulated term enters the CPR at 2x
//       (for a fused pair the low lane's shifted-out MSB fills the high lane's
//       LSB). This keeps acc_i / pe_out in native units and the register at the
//       true value.
//     - const MUX (sel_const_i): the per-mode C from const_sqr - CH/CL (c_i hi/lo)
//       on Im/real outputs, RH/RL (c_neg_i hi/lo) on the negated Re outputs, with
//       RH = sign(RL). Re outputs sit on lanes 0-5 (mode 10 Re on L1 pairs
//       (0,1)(4,5); modes 11/12 Re on L2 pair (2,3)); lanes 6/7 are never Re.
//     - CPR 8:2 (EXT=3) folds {6 taps, C, 2*acc} -> 2 rows; add_n resolves them
//       plus the inter-lane carry into the 20-bit window (= 2*R_new).
//     - the /2: an arithmetic >>1 between add_n and the register, with an H->L
//       cross-lane bit (the high lane's shifted-out LSB fills the low lane's MSB
//       on fused outputs). The register holds the true result R_new = 1/2*tap +
//       acc - no decay, no 2x register.
//     - the 2-bit style inter-lane carry chains L(odd) -> gate_n(prop_carry_i) ->
//       H(even).cin (CARRY=3 here, 8 rows overflow bit 19 by up to 3 bits); the
//       <<1's low-lane overflow rides this same chain.
//
//   Pipeline depth is identical to acc_array: one register stage (the PE/alpha/
//   beta arrays that feed it run in parallel). Signedness is carried by the
//   40-bit sign-extension, so the CPR/add run unsigned. Fixed to the PE; controls
//   are shared across all lanes.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module acc_array_sqr #(
    localparam int NUM_LANE   = 8,
    localparam int PE_WIDTH   = 20,
    localparam int FUSE       = 40,
    localparam int NUM_OP     = 3,
    localparam int EXT        = 3,
    localparam int CPR_WIDTH  = PE_WIDTH + EXT,
    localparam int CARRY      = 3,
    localparam int NUM_LVL    = 4,
    localparam int NUM_L0     = 8,
    localparam int NUM_L1     = 4,
    localparam int NUM_L2     = 2,
    localparam int L0_TAP     = 19,
    localparam int L1_TAP     = 30,
    localparam int L2_TAP     = 38,
    localparam int L3_TAP     = 39,
    localparam int SEL_WIDTH  = 2,
    localparam int C_WIDTH    = 32,
    localparam int CNEG_WIDTH = 8
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,

    input  logic [    L0_TAP-1:0] pe_l0_sum_i   [0:NUM_L0-1],
    input  logic [    L0_TAP-1:0] pe_l0_carry_i [0:NUM_L0-1],
    input  logic [    L1_TAP-1:0] pe_l1_sum_i   [0:NUM_L1-1],
    input  logic [    L1_TAP-1:0] pe_l1_carry_i [0:NUM_L1-1],
    input  logic [    L2_TAP-1:0] pe_l2_sum_i   [0:NUM_L2-1],
    input  logic [    L2_TAP-1:0] pe_l2_carry_i [0:NUM_L2-1],
    input  logic [    L3_TAP-1:0] pe_l3_sum_i,
    input  logic [    L3_TAP-1:0] pe_l3_carry_i,

    input  logic [    L0_TAP-1:0] a_l0_sum_i    [0:NUM_L0-1],
    input  logic [    L0_TAP-1:0] a_l0_carry_i  [0:NUM_L0-1],
    input  logic [    L1_TAP-1:0] a_l1_sum_i    [0:NUM_L1-1],
    input  logic [    L1_TAP-1:0] a_l1_carry_i  [0:NUM_L1-1],
    input  logic [    L2_TAP-1:0] a_l2_sum_i    [0:NUM_L2-1],
    input  logic [    L2_TAP-1:0] a_l2_carry_i  [0:NUM_L2-1],
    input  logic [    L3_TAP-1:0] a_l3_sum_i,
    input  logic [    L3_TAP-1:0] a_l3_carry_i,

    input  logic [    L0_TAP-1:0] b_l0_sum_i    [0:NUM_L0-1],
    input  logic [    L0_TAP-1:0] b_l0_carry_i  [0:NUM_L0-1],
    input  logic [    L1_TAP-1:0] b_l1_sum_i    [0:NUM_L1-1],
    input  logic [    L1_TAP-1:0] b_l1_carry_i  [0:NUM_L1-1],
    input  logic [    L2_TAP-1:0] b_l2_sum_i    [0:NUM_L2-1],
    input  logic [    L2_TAP-1:0] b_l2_carry_i  [0:NUM_L2-1],
    input  logic [    L3_TAP-1:0] b_l3_sum_i,
    input  logic [    L3_TAP-1:0] b_l3_carry_i,

    input  logic [   C_WIDTH-1:0] c_i,
    input  logic [CNEG_WIDTH-1:0] c_neg_i,
    input  logic [  PE_WIDTH-1:0] acc_i         [0:NUM_LANE-1],
    input  logic [ SEL_WIDTH-1:0] sel_out_i,
    input  logic                  sel_acc_i,
    input  logic [ SEL_WIDTH-1:0] sel_const_i,
    input  logic                  prop_carry_i,
    output logic [  PE_WIDTH-1:0] pe_out_o      [0:NUM_LANE-1]
);

    logic [  L0_TAP-1:0] l0s        [0:NUM_OP-1][0:NUM_L0-1];
    logic [  L0_TAP-1:0] l0c        [0:NUM_OP-1][0:NUM_L0-1];
    logic [  L1_TAP-1:0] l1s        [0:NUM_OP-1][0:NUM_L1-1];
    logic [  L1_TAP-1:0] l1c        [0:NUM_OP-1][0:NUM_L1-1];
    logic [  L2_TAP-1:0] l2s        [0:NUM_OP-1][0:NUM_L2-1];
    logic [  L2_TAP-1:0] l2c        [0:NUM_OP-1][0:NUM_L2-1];
    logic [  L3_TAP-1:0] l3s        [0:NUM_OP-1];
    logic [  L3_TAP-1:0] l3c        [0:NUM_OP-1];

    logic [PE_WIDTH-1:0] w_sum      [0:NUM_OP-1][0:NUM_LANE-1][0:NUM_LVL-1];
    logic [PE_WIDTH-1:0] w_car      [0:NUM_OP-1][0:NUM_LANE-1][0:NUM_LVL-1];

    logic [PE_WIDTH-1:0] acc_sel    [0:NUM_LANE-1];
    logic [PE_WIDTH-1:0] acc_x2     [0:NUM_LANE-1];
    logic [PE_WIDTH-1:0] c_sel      [0:NUM_LANE-1];
    logic [PE_WIDTH-1:0] rd         [0:NUM_LANE-1];
    logic [PE_WIDTH-1:0] half       [0:NUM_LANE-1];
    logic [PE_WIDTH-1:0] reg_q      [0:NUM_LANE-1];
    logic [   CARRY-1:0] lane_cin   [0:NUM_LANE-1];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [   CARRY-1:0] lane_carry [0:NUM_LANE-1];
    /* verilator lint_on UNUSEDSIGNAL */

    logic [PE_WIDTH-1:0] c_hi, c_lo, r_hi, r_lo;
    logic                fused;

    assign fused = |sel_out_i;
    assign c_hi  = PE_WIDTH'(c_i[C_WIDTH-1:PE_WIDTH]);
    assign c_lo  = c_i[PE_WIDTH-1:0];
    assign r_lo  = PE_WIDTH'($signed(c_neg_i));
    assign r_hi  = {PE_WIDTH{c_neg_i[CNEG_WIDTH-1]}};

    genvar op, g, n, l;

    generate

        for (n = 0; n < NUM_L0; n++) begin : gen_asm_l0
            assign l0s[0][n] = pe_l0_sum_i[n];  assign l0c[0][n] = pe_l0_carry_i[n];
            assign l0s[1][n] = a_l0_sum_i[n];   assign l0c[1][n] = a_l0_carry_i[n];
            assign l0s[2][n] = b_l0_sum_i[n];   assign l0c[2][n] = b_l0_carry_i[n];
        end

        for (n = 0; n < NUM_L1; n++) begin : gen_asm_l1
            assign l1s[0][n] = pe_l1_sum_i[n];  assign l1c[0][n] = pe_l1_carry_i[n];
            assign l1s[1][n] = a_l1_sum_i[n];   assign l1c[1][n] = a_l1_carry_i[n];
            assign l1s[2][n] = b_l1_sum_i[n];   assign l1c[2][n] = b_l1_carry_i[n];
        end

        for (n = 0; n < NUM_L2; n++) begin : gen_asm_l2
            assign l2s[0][n] = pe_l2_sum_i[n];  assign l2c[0][n] = pe_l2_carry_i[n];
            assign l2s[1][n] = a_l2_sum_i[n];   assign l2c[1][n] = a_l2_carry_i[n];
            assign l2s[2][n] = b_l2_sum_i[n];   assign l2c[2][n] = b_l2_carry_i[n];
        end

        assign l3s[0] = pe_l3_sum_i; assign l3c[0] = pe_l3_carry_i;
        assign l3s[1] = a_l3_sum_i;  assign l3c[1] = a_l3_carry_i;
        assign l3s[2] = b_l3_sum_i;  assign l3c[2] = b_l3_carry_i;

        for (op = 0; op < NUM_OP; op++) begin : gen_op
            for (g = 0; g < NUM_LANE; g++) begin : gen_win

                /* verilator lint_off UNUSEDSIGNAL */
                logic [FUSE-1:0] l1sf, l1cf;
                assign w_sum[op][g][0] = PE_WIDTH'($signed(l0s[op][g]));
                assign w_car[op][g][0] = PE_WIDTH'($signed(l0c[op][g]));

                assign l1sf = FUSE'($signed(l1s[op][g/2]));
                assign l1cf = FUSE'($signed(l1c[op][g/2]));

                if (g % 2 == 0) begin : gen_l1_h
                    assign w_sum[op][g][1] = l1sf[FUSE-1:PE_WIDTH];
                    assign w_car[op][g][1] = l1cf[FUSE-1:PE_WIDTH];
                end else begin : gen_l1_l
                    assign w_sum[op][g][1] = l1sf[PE_WIDTH-1:0];
                    assign w_car[op][g][1] = l1cf[PE_WIDTH-1:0];
                end

                if (g == 2 || g == 3 || g == 6 || g == 7) begin : gen_l2
                    localparam int N2 = (g <= 3) ? 0 : 1;
                    logic [FUSE-1:0] l2sf, l2cf;
                    assign l2sf = FUSE'($signed(l2s[op][N2]));
                    assign l2cf = FUSE'($signed(l2c[op][N2]));
                    if (g % 2 == 0) begin : gen_l2_h
                        assign w_sum[op][g][2] = l2sf[FUSE-1:PE_WIDTH];
                        assign w_car[op][g][2] = l2cf[FUSE-1:PE_WIDTH];
                    end else begin : gen_l2_l
                        assign w_sum[op][g][2] = l2sf[PE_WIDTH-1:0];
                        assign w_car[op][g][2] = l2cf[PE_WIDTH-1:0];
                    end
                end else begin : gen_no_l2
                    assign w_sum[op][g][2] = '0;
                    assign w_car[op][g][2] = '0;
                end

                if (g == 6 || g == 7) begin : gen_l3
                    logic [FUSE-1:0] l3sf, l3cf;
                    assign l3sf = FUSE'($signed(l3s[op]));
                    assign l3cf = FUSE'($signed(l3c[op]));
                    if (g % 2 == 0) begin : gen_l3_h
                        assign w_sum[op][g][3] = l3sf[FUSE-1:PE_WIDTH];
                        assign w_car[op][g][3] = l3cf[FUSE-1:PE_WIDTH];
                    end else begin : gen_l3_l
                        assign w_sum[op][g][3] = l3sf[PE_WIDTH-1:0];
                        assign w_car[op][g][3] = l3cf[PE_WIDTH-1:0];
                    end
                end else begin : gen_no_l3
                    assign w_sum[op][g][3] = '0;
                    assign w_car[op][g][3] = '0;
                end
                /* verilator lint_on UNUSEDSIGNAL */
            end
        end

        for (g = 0; g < NUM_LANE; g++) begin : gen_lane

            localparam bit IS_EVEN  = (g % 2 == 0);
            localparam bit IS_RE_L1 = (g == 0 || g == 1 || g == 4 || g == 5);
            localparam bit IS_RE_L2 = (g == 2 || g == 3);

            logic [PE_WIDTH-1:0] tap_sum [0:NUM_OP-1];
            logic [PE_WIDTH-1:0] tap_car [0:NUM_OP-1];

            for (op = 0; op < NUM_OP; op++) begin : gen_tapmux
                logic [2*PE_WIDTH-1:0] tapmux_in [0:NUM_LVL-1];
                logic [2*PE_WIDTH-1:0] tapmux_out;
                for (l = 0; l < NUM_LVL; l++) begin : gen_pack
                    assign tapmux_in[l] = {w_car[op][g][l], w_sum[op][g][l]};
                end
                mux_n #(.WIDTH(2*PE_WIDTH), .SIZE(NUM_LVL)) tap_mux_i (
                    .in_i(tapmux_in), .sel_i(sel_out_i), .out_o(tapmux_out)
                );
                assign tap_sum[op] = tapmux_out[PE_WIDTH-1:0];
                assign tap_car[op] = tapmux_out[2*PE_WIDTH-1:PE_WIDTH];
            end

            logic [PE_WIDTH-1:0] accmux_in [0:1];

            assign accmux_in[0] = acc_i[g];
            assign accmux_in[1] = reg_q[g];

            mux_n #(.WIDTH(PE_WIDTH), .SIZE(2)) acc_mux_i (
                .in_i(accmux_in), .sel_i(sel_acc_i), .out_o(acc_sel[g])
            );

            if (IS_EVEN) begin : gen_accx2_h
                logic [0:0] msb_in  [0:0];
                logic [0:0] msb_out [0:0];
                assign msb_in[0] = acc_sel[g+1][PE_WIDTH-1];
                gate_n #(.WIDTH(1), .SIZE(1)) gate_n_msb_i (
                    .in_i(msb_in), .sel_i(~fused), .out_o(msb_out)
                );
                assign acc_x2[g] = {acc_sel[g][PE_WIDTH-2:0], msb_out[0]};
            end else begin : gen_accx2_l
                assign acc_x2[g] = {acc_sel[g][PE_WIDTH-2:0], 1'b0};
            end

            logic [PE_WIDTH-1:0] cmux_in [0:3];

            assign cmux_in[0] = c_lo;
            assign cmux_in[1] = IS_EVEN ? c_hi : c_lo;
            assign cmux_in[2] = IS_RE_L1 ? (IS_EVEN ? r_hi : r_lo)
                                         : (IS_EVEN ? c_hi : c_lo);
            assign cmux_in[3] = IS_RE_L2 ? (IS_EVEN ? r_hi : r_lo)
                                         : (IS_EVEN ? c_hi : c_lo);

            mux_n #(.WIDTH(PE_WIDTH), .SIZE(4)) c_mux_i (
                .in_i(cmux_in), .sel_i(sel_const_i), .out_o(c_sel[g])
            );

            logic [ PE_WIDTH-1:0] cpr_in [0:7];
            logic [CPR_WIDTH-1:0] cpr_sum, cpr_car;

            assign cpr_in[0] = tap_sum[0];
            assign cpr_in[1] = tap_car[0];
            assign cpr_in[2] = tap_sum[1];
            assign cpr_in[3] = tap_car[1];
            assign cpr_in[4] = tap_sum[2];
            assign cpr_in[5] = tap_car[2];
            assign cpr_in[6] = c_sel[g];
            assign cpr_in[7] = acc_x2[g];

            cpr_w_n #(.IN_WIDTH(PE_WIDTH), .IN_SIZE(8), .EXT(EXT), .IS_SIGNED(1'b0)) cpr_w_n_i (
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
                gate_n #(.WIDTH(CARRY), .SIZE(1)) gate_n_i (
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

            assign reg_q[g] = rq[0];
        end
    endgenerate

    assign pe_out_o = reg_q;

endmodule
