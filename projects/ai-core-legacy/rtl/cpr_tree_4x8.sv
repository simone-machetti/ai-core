// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Three-stage 4:2 compression tree. Reduces PP_SIZE partial products of
//   PP_WIDTH bits plus ACC_SIZE 48-bit accumulators to a single 48-bit result.
//
//   Stage structure:
//     Stage 0: 8 groups of PP_SIZE/8 inputs compressed to 2 per group;
//              pipeline register inserted here when IS_PIPELINED = 1.
//     Stage 1: 4 groups of 4 inputs compressed to 2 per group.
//     Stage 2: 2 groups of 4 inputs compressed to 2 per group.
//     Final:   4 outputs + ACC_SIZE accumulators fed into cpr_n_2, then add_n.
//
//   Between each stage, ext_n sign/zero-extends (and optionally shifts) the
//   compressor outputs to grow bit width. The is_signed_i / is_shift_i arrays
//   (EXT_NUM = 15 entries) select the extension mode for every stage/lane.
//
// Parameters:
//   IS_PIPELINED - 1 = insert pipeline register after stage 0 (3-cycle total
//                      latency from input FFs); 0 = no register (2-cycle)
//   PP_SIZE      - number of partial product inputs (must be a multiple of 8)
//   PP_WIDTH     - bit width of each partial product (must be <= 48)
//   ACC_SIZE     - number of 48-bit accumulator inputs added at the final stage
// -----------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off GENUNNAMED */

`timescale 1 ns/1 ps

module cpr_tree_4x8 #(
    parameter bit IS_PIPELINED = 1,
    parameter int PP_SIZE      = 64,
    parameter int PP_WIDTH     = 12,
    parameter int ACC_SIZE     = 1,

    localparam int ACC_WIDTH = 48,
    localparam int EXT_NUM   = 15,
    localparam int OUT_WIDTH = ACC_WIDTH
)(
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic [ACC_WIDTH-1:0] acc_i       [0:((ACC_SIZE > 0) ? ACC_SIZE-1 : 0)],
    input  logic                 is_signed_i [ 0:EXT_NUM-1],
    input  logic                 is_shift_i  [ 0:EXT_NUM-1],
    input  logic [ PP_WIDTH-1:0] pp_i        [ 0:PP_SIZE-1],
    output logic [OUT_WIDTH-1:0] out_o
);

    function automatic int pow2(input int n);
        return 1 << n;
    endfunction

    function automatic int get_in_size(input int stage);
        begin
            if (stage == 0) begin
                get_in_size = PP_SIZE / 8;
            end else begin
                get_in_size = 4;
            end
        end
    endfunction

    function automatic int gen_in_width(input int stage);
        int tmp;
        begin
            if (stage == 0) begin
                gen_in_width = PP_WIDTH;
            end else if (stage == 1) begin
                gen_in_width = PP_WIDTH + 4;
            end else if (stage == 2) begin
                tmp          = PP_WIDTH + 4;
                gen_in_width = tmp + 8;
            end else if (stage == 3) begin
                tmp          = PP_WIDTH + 4;
                tmp          = tmp + 8;
                gen_in_width = tmp + 8;
            end else begin
                gen_in_width = PP_WIDTH;
            end
        end
    endfunction

    function automatic int get_sel_ext(input int stage, input int lane);
        int stage_0_offset = 0;
        int stage_1_offset = 8;
        int stage_2_offset = 12;
        int stage_3_offset = 14;
        begin
            if (stage == 0) begin
                get_sel_ext = stage_0_offset + lane;
            end else if (stage == 1) begin
                get_sel_ext = stage_1_offset + lane;
            end else if (stage == 2) begin
                get_sel_ext = stage_2_offset + lane;
            end else if (stage == 3) begin
                get_sel_ext = stage_3_offset + lane;
            end else begin
                get_sel_ext = stage_0_offset + lane;
            end
        end
    endfunction

    genvar stage, lane, i;
    generate

        if (PP_WIDTH > ACC_WIDTH) begin

            assign out_o = '0;

            initial $fatal(1, "cpr_tree: PP_WIDTH must be <= 48, got %0d", PP_WIDTH);

        end else begin

            localparam int NUM_STAGES = 3;

            logic [OUT_WIDTH-1:0] tmp [0:NUM_STAGES][0:PP_SIZE-1];

            for (i = 0; i < PP_SIZE; i++)
                assign tmp[0][i][PP_WIDTH-1:0] = pp_i[i];

            for (stage = 0; stage < NUM_STAGES; stage++) begin

                localparam int CPR_N_2_IN_SIZE      = get_in_size(stage);
                localparam int CPR_N_2_IN_WIDTH     = gen_in_width(stage);
                localparam int CPR_N_2_MAX_EXT_BITS = 0;
                localparam int NUM_LANES            = 8 / pow2(stage);

                for (lane = 0; lane < NUM_LANES; lane++) begin

                    logic [CPR_N_2_IN_WIDTH-1:0] cpr_n_2_in [0:CPR_N_2_IN_SIZE-1];
                    logic [CPR_N_2_IN_WIDTH-1:0] cpr_n_2_sum;
                    logic [CPR_N_2_IN_WIDTH-1:0] cpr_n_2_carry;

                    for (i = 0; i < CPR_N_2_IN_SIZE; i++)
                        assign cpr_n_2_in[i] = tmp[stage][lane*CPR_N_2_IN_SIZE+i][CPR_N_2_IN_WIDTH-1:0];

                    cpr_n_2 #(
                        .IN_SIZE     (CPR_N_2_IN_SIZE),
                        .IN_WIDTH    (CPR_N_2_IN_WIDTH),
                        .MAX_EXT_BITS(CPR_N_2_MAX_EXT_BITS)
                    ) cpr_n_2_i (
                        .in_i   (cpr_n_2_in),
                        .sum_o  (cpr_n_2_sum),
                        .carry_o(cpr_n_2_carry)
                    );

                    localparam int EXT_N_IN_SIZE   = 2;
                    localparam int EXT_N_EXTEND    = stage == 0 ? 4 : 8;
                    localparam int EXT_N_SEL_EXT   = get_sel_ext(stage, lane);
                    localparam int EXT_N_OUT_WIDTH = CPR_N_2_IN_WIDTH + EXT_N_EXTEND;

                    logic [CPR_N_2_IN_WIDTH-1:0] ext_n_in  [0:EXT_N_IN_SIZE-1];
                    logic [ EXT_N_OUT_WIDTH-1:0] ext_n_out [0:EXT_N_IN_SIZE-1];

                    assign ext_n_in[0] = cpr_n_2_sum;
                    assign ext_n_in[1] = cpr_n_2_carry;

                    ext_n #(
                        .IN_SIZE (EXT_N_IN_SIZE),
                        .IN_WIDTH(CPR_N_2_IN_WIDTH),
                        .EXTEND  (EXT_N_EXTEND)
                    ) ext_n_i (
                        .is_signed_i(is_signed_i[EXT_N_SEL_EXT]),
                        .is_shift_i (is_shift_i[EXT_N_SEL_EXT]),
                        .in_i       (ext_n_in),
                        .out_o      (ext_n_out)
                    );

                    if (IS_PIPELINED) begin

                        if (stage == 0) begin

                            logic [EXT_N_OUT_WIDTH-1:0] ext_n_out_tmp [0:EXT_N_IN_SIZE-1];

                            ff_n #(
                                .WIDTH(EXT_N_OUT_WIDTH),
                                .SIZE (EXT_N_IN_SIZE)
                            ) ff_n_i (
                                .clk_i (clk_i),
                                .rst_ni(rst_ni),
                                .d_i   (ext_n_out),
                                .q_o   (ext_n_out_tmp)
                            );

                            assign tmp[stage+1][lane*EXT_N_IN_SIZE+0][EXT_N_OUT_WIDTH-1:0] = ext_n_out_tmp[0];
                            assign tmp[stage+1][lane*EXT_N_IN_SIZE+1][EXT_N_OUT_WIDTH-1:0] = ext_n_out_tmp[1];

                        end else begin

                            assign tmp[stage+1][lane*EXT_N_IN_SIZE+0][EXT_N_OUT_WIDTH-1:0] = ext_n_out[0];
                            assign tmp[stage+1][lane*EXT_N_IN_SIZE+1][EXT_N_OUT_WIDTH-1:0] = ext_n_out[1];
                            
                        end

                    end else begin

                        assign tmp[stage+1][lane*EXT_N_IN_SIZE+0][EXT_N_OUT_WIDTH-1:0] = ext_n_out[0];
                        assign tmp[stage+1][lane*EXT_N_IN_SIZE+1][EXT_N_OUT_WIDTH-1:0] = ext_n_out[1];

                    end
                end
            end

            localparam int EXT_N_LAST_IN_SIZE   = 4;
            localparam int EXT_N_LAST_IN_WIDTH  = gen_in_width(3);
            localparam int EXT_N_LAST_EXTEND    = ACC_WIDTH - EXT_N_LAST_IN_WIDTH;
            localparam int EXT_N_LAST_SEL_EXT   = get_sel_ext(3, 0);
            localparam int EXT_N_LAST_OUT_WIDTH = EXT_N_LAST_IN_WIDTH + EXT_N_LAST_EXTEND;

            logic [ EXT_N_LAST_IN_WIDTH-1:0] ext_n_last_in  [0:EXT_N_LAST_IN_SIZE-1];
            logic [EXT_N_LAST_OUT_WIDTH-1:0] ext_n_last_out [0:EXT_N_LAST_IN_SIZE-1];

            for (i = 0; i < EXT_N_LAST_IN_SIZE; i++)
                assign ext_n_last_in[i] = tmp[3][i][EXT_N_LAST_IN_WIDTH-1:0];

            ext_n #(
                .IN_SIZE (EXT_N_LAST_IN_SIZE),
                .IN_WIDTH(EXT_N_LAST_IN_WIDTH),
                .EXTEND  (EXT_N_LAST_EXTEND)
            ) ext_n_i (
                .is_signed_i(is_signed_i[EXT_N_LAST_SEL_EXT]),
                .is_shift_i (is_shift_i[EXT_N_LAST_SEL_EXT]),
                .in_i       (ext_n_last_in),
                .out_o      (ext_n_last_out)
            );

            localparam int CPR_N_2_LAST_IN_SIZE      = EXT_N_LAST_IN_SIZE + ACC_SIZE;
            localparam int CPR_N_2_LAST_IN_WIDTH     = EXT_N_LAST_OUT_WIDTH;
            localparam int CPR_N_2_LAST_MAX_EXT_BITS = 0;

            logic [CPR_N_2_LAST_IN_WIDTH-1:0] cpr_n_2_last_in [0:CPR_N_2_LAST_IN_SIZE-1];
            logic [CPR_N_2_LAST_IN_WIDTH-1:0] cpr_n_2_last_sum;
            logic [CPR_N_2_LAST_IN_WIDTH-1:0] cpr_n_2_last_carry;

            for (i = 0; i < EXT_N_LAST_IN_SIZE; i++)
                assign cpr_n_2_last_in[i] = ext_n_last_out[i];

            for (i = 0; i < ACC_SIZE; i++)
                assign cpr_n_2_last_in[EXT_N_LAST_IN_SIZE+i] = acc_i[i];

            cpr_n_2 #(
                .IN_SIZE     (CPR_N_2_LAST_IN_SIZE),
                .IN_WIDTH    (CPR_N_2_LAST_IN_WIDTH),
                .MAX_EXT_BITS(CPR_N_2_LAST_MAX_EXT_BITS)
            ) cpr_n_2_last_i (
                .in_i   (cpr_n_2_last_in),
                .sum_o  (cpr_n_2_last_sum),
                .carry_o(cpr_n_2_last_carry)
            );

            logic [OUT_WIDTH:0] out;

            add_n #(
                .IN_WIDTH(CPR_N_2_LAST_IN_WIDTH)
            ) add_n_i (
                .in_0_i(cpr_n_2_last_sum),
                .in_1_i(cpr_n_2_last_carry),
                .out_o (out)
            );

            assign out_o = out[OUT_WIDTH-1:0];

        end

    endgenerate

endmodule
