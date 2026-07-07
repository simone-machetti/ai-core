// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Eight-lane accumulator - the final stage of the PE. It reads the carry-save
//   taps of pe_array (l0/l1/l2/l3, each a sum/carry pair), resolves the one the
//   mode selects into a binary value, optionally accumulates it, and drives eight
//   20-bit outputs. Each lane is 20 bits wide; a result wider than 20 bits is
//   carried across a lane pair (0,1)(2,3)(4,5)(6,7) - the even lane holds the
//   high half, the odd lane the low half - so two 20-bit lanes fuse into one
//   40-bit result.
//
//   Per lane:
//     - sign-extend the selected tap (sum, carry) to 40 bits and window it: the
//       even lane takes bits [39:20] (H), the odd lane bits [19:0] (L). L0 taps
//       are single-lane (<=16-bit value) and use the low window directly.
//     - tap-level MUX (sel_out_i, shared) picks which tree level this lane reads.
//     - accumulate MUX (sel_acc_i, shared) picks the third CPR row: 0 = external
//       accumulator word acc_i[k], 1 = the lane's own register feedback.
//     - CPR 3:2 folds {tap_sum, tap_carry, acc} to two rows; add_n resolves them
//       plus a carry-in into the 20-bit window value and a 2-bit carry-out.
//     - the 2-bit carry chains L(odd) -> gate_n(prop_carry_i) -> H(even).cin so
//       the pair reconstructs the full value; a standalone lane ignores it.
//     - a register holds the result (feedback for accumulation) and drives pe_out.
//
//   The 3-row window fold overflows bit 19 by up to 2 bits, so the CPR carries
//   two guard bits (EXT = 2 -> 22-bit rows) and the inter-lane carry is 2 bits.
//   Signedness is handled by the 40-bit sign-extension, so the CPR/add run
//   unsigned. Fixed to the PE; controls are shared across all lanes.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module acc_array #(
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
    localparam int SEL_WIDTH = 2
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
    input  logic [ PE_WIDTH-1:0] acc_i      [0:NUM_LANE-1],
    input  logic [SEL_WIDTH-1:0] sel_out_i,
    input  logic                 sel_acc_i,
    input  logic                 prop_carry_i,
    output logic [ PE_WIDTH-1:0] pe_out_o   [0:NUM_LANE-1]
);

    logic [ PE_WIDTH-1:0] w_sum [0:NUM_LANE-1][0:NUM_LVL-1];
    logic [ PE_WIDTH-1:0] w_car [0:NUM_LANE-1][0:NUM_LVL-1];

    logic [ PE_WIDTH-1:0] reg_q [0:NUM_LANE-1];
    logic [    CARRY-1:0] lane_cin [0:NUM_LANE-1];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [    CARRY-1:0] lane_carry [0:NUM_LANE-1];
    /* verilator lint_on UNUSEDSIGNAL */

    genvar g, l;

    generate
        for (g = 0; g < NUM_LANE; g++) begin : gen_lane

            /* verilator lint_off UNUSEDSIGNAL */
            assign w_sum[g][0] = PE_WIDTH'($signed(l0_sum_i[g]));
            assign w_car[g][0] = PE_WIDTH'($signed(l0_carry_i[g]));

            logic [FUSE-1:0] l1s, l1c;

            assign l1s = FUSE'($signed(l1_sum_i[g/2]));
            assign l1c = FUSE'($signed(l1_carry_i[g/2]));

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
            end

            if (g == 6 || g == 7) begin : gen_l3
                logic [FUSE-1:0] l3s, l3c;
                assign l3s = FUSE'($signed(l3_sum_i));
                assign l3c = FUSE'($signed(l3_carry_i));
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
            end
            /* verilator lint_on UNUSEDSIGNAL */

            logic [2*PE_WIDTH-1:0] tapmux_in [0:NUM_LVL-1];
            logic [2*PE_WIDTH-1:0] tapmux_out;

            for (l = 0; l < NUM_LVL; l++) begin : gen_pack
                assign tapmux_in[l] = {w_car[g][l], w_sum[g][l]};
            end

            mux_n #(.WIDTH(2*PE_WIDTH), .SIZE(NUM_LVL)) tap_mux_i (
                .in_i(tapmux_in), .sel_i(sel_out_i), .out_o(tapmux_out)
            );

            logic [PE_WIDTH-1:0] tap_sum, tap_car;

            assign tap_sum = tapmux_out[PE_WIDTH-1:0];
            assign tap_car = tapmux_out[2*PE_WIDTH-1:PE_WIDTH];

            logic [PE_WIDTH-1:0] accmux_in [0:1];
            logic [PE_WIDTH-1:0] acc_sel;

            assign accmux_in[0] = acc_i[g];
            assign accmux_in[1] = reg_q[g];

            mux_n #(.WIDTH(PE_WIDTH), .SIZE(2)) acc_mux_i (
                .in_i(accmux_in), .sel_i(sel_acc_i), .out_o(acc_sel)
            );

            logic [ PE_WIDTH-1:0] cpr_in [0:2];
            logic [CPR_WIDTH-1:0] cpr_sum, cpr_car;

            assign cpr_in[0] = tap_sum;
            assign cpr_in[1] = tap_car;
            assign cpr_in[2] = acc_sel;

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

            assign reg_q[g] = rq[0];
        end
    endgenerate

    assign pe_out_o = reg_q;

endmodule
