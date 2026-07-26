// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for align_cell_bfp. Instantiates an H/L lane pair
//   (both signed, shared exponents, chain wired H -> L) plus an unsigned
//   standalone instance sharing the H stimulus. Every vector is checked twice,
//   with the L chain disabled and enabled. Golden model is value-level: each
//   row of the smaller-exponent bundle must equal the row right-shifted by
//   (max exponent - bundle exponent) - arithmetic for the signed instances,
//   logical for the unsigned one, and the fused 2*WIDTH shift of
//   {H row, L row} for the chained L instance - while the winner bundle must
//   pass through bit-identical and exp_o must equal the max on all instances.
//   Exponent deltas are corner-biased around 0 / 1 / WIDTH / 2*WIDTH and the
//   row corners use the named constants.
//
// Parameters:
//   WIDTH     - row width
//   SIZE_0    - number of rows in bundle 0
//   SIZE_1    - number of rows in bundle 1
//   EXP_WIDTH - exponent width
//   NUM_RAND  - number of random vectors
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */
module tb_align_cell_bfp #(
    parameter  int WIDTH     = 20,
    parameter  int SIZE_0    = 2,
    parameter  int SIZE_1    = 2,
    parameter  int EXP_WIDTH = 8,
    parameter  int NUM_RAND  = 2000,
    localparam int E_TOP     = 2 ** EXP_WIDTH - 1
);

    localparam logic [    WIDTH-1:0] ZERO     = '0;
    localparam logic [    WIDTH-1:0] ALL_ONES = '1;
    localparam logic [    WIDTH-1:0] MAX_POS  = {1'b0, {(WIDTH-1){1'b1}}};
    localparam logic [    WIDTH-1:0] MIN_NEG  = {1'b1, {(WIDTH-1){1'b0}}};
    localparam logic [EXP_WIDTH-1:0] E_MIN    = '0;
    localparam logic [EXP_WIDTH-1:0] E_MAX    = '1;
    localparam logic [EXP_WIDTH-1:0] E_MID    = {1'b1, {(EXP_WIDTH-1){1'b0}}};

    logic [    WIDTH-1:0] in_h0   [0:SIZE_0-1];
    logic [    WIDTH-1:0] in_h1   [0:SIZE_1-1];
    logic [    WIDTH-1:0] in_l0   [0:SIZE_0-1];
    logic [    WIDTH-1:0] in_l1   [0:SIZE_1-1];
    logic [EXP_WIDTH-1:0] exp_0;
    logic [EXP_WIDTH-1:0] exp_1;
    logic                 chain_en;

    logic [    WIDTH-1:0] zero_0  [0:SIZE_0-1];
    logic [    WIDTH-1:0] zero_1  [0:SIZE_1-1];

    logic [    WIDTH-1:0] h_out_0 [0:SIZE_0-1];
    logic [    WIDTH-1:0] h_out_1 [0:SIZE_1-1];
    logic [    WIDTH-1:0] h_ch_0  [0:SIZE_0-1];
    logic [    WIDTH-1:0] h_ch_1  [0:SIZE_1-1];
    logic [EXP_WIDTH-1:0] h_exp;

    logic [    WIDTH-1:0] l_out_0 [0:SIZE_0-1];
    logic [    WIDTH-1:0] l_out_1 [0:SIZE_1-1];
    logic [    WIDTH-1:0] l_ch_0  [0:SIZE_0-1];
    logic [    WIDTH-1:0] l_ch_1  [0:SIZE_1-1];
    logic [EXP_WIDTH-1:0] l_exp;

    logic [    WIDTH-1:0] u_out_0 [0:SIZE_0-1];
    logic [    WIDTH-1:0] u_out_1 [0:SIZE_1-1];
    logic [    WIDTH-1:0] u_ch_0  [0:SIZE_0-1];
    logic [    WIDTH-1:0] u_ch_1  [0:SIZE_1-1];
    logic [EXP_WIDTH-1:0] u_exp;

    genvar z;
    generate
        for (z = 0; z < SIZE_0; z++) begin : gen_zero_0
            assign zero_0[z] = '0;
        end
        for (z = 0; z < SIZE_1; z++) begin : gen_zero_1
            assign zero_1[z] = '0;
        end
    endgenerate

    align_cell_bfp #(
        .WIDTH    (WIDTH),
        .SIZE_0   (SIZE_0),
        .SIZE_1   (SIZE_1),
        .EXP_WIDTH(EXP_WIDTH),
        .IS_SIGNED(1'b1)
    ) align_cell_bfp_h_i (
        .in_0_i    (in_h0),
        .exp_0_i   (exp_0),
        .in_1_i    (in_h1),
        .exp_1_i   (exp_1),
        .chain_en_i(1'b0),
        .chain_0_i (zero_0),
        .chain_1_i (zero_1),
        .chain_0_o (h_ch_0),
        .chain_1_o (h_ch_1),
        .out_0_o   (h_out_0),
        .out_1_o   (h_out_1),
        .exp_o     (h_exp)
    );

    align_cell_bfp #(
        .WIDTH    (WIDTH),
        .SIZE_0   (SIZE_0),
        .SIZE_1   (SIZE_1),
        .EXP_WIDTH(EXP_WIDTH),
        .IS_SIGNED(1'b1)
    ) align_cell_bfp_l_i (
        .in_0_i    (in_l0),
        .exp_0_i   (exp_0),
        .in_1_i    (in_l1),
        .exp_1_i   (exp_1),
        .chain_en_i(chain_en),
        .chain_0_i (h_ch_0),
        .chain_1_i (h_ch_1),
        .chain_0_o (l_ch_0),
        .chain_1_o (l_ch_1),
        .out_0_o   (l_out_0),
        .out_1_o   (l_out_1),
        .exp_o     (l_exp)
    );

    align_cell_bfp #(
        .WIDTH    (WIDTH),
        .SIZE_0   (SIZE_0),
        .SIZE_1   (SIZE_1),
        .EXP_WIDTH(EXP_WIDTH),
        .IS_SIGNED(1'b0)
    ) align_cell_bfp_u_i (
        .in_0_i    (in_h0),
        .exp_0_i   (exp_0),
        .in_1_i    (in_h1),
        .exp_1_i   (exp_1),
        .chain_en_i(1'b0),
        .chain_0_i (zero_0),
        .chain_1_i (zero_1),
        .chain_0_o (u_ch_0),
        .chain_1_o (u_ch_1),
        .out_0_o   (u_out_0),
        .out_1_o   (u_out_1),
        .exp_o     (u_exp)
    );

    task automatic check_row(input string tag, input int r,
                             input logic [WIDTH-1:0] dut_val,
                             input logic [WIDTH-1:0] gold_val);
        if (dut_val !== gold_val) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("align_cell_bfp: %s row %0d: dut %h gold %h (exp_0 %0d exp_1 %0d chain %b)",
                   tag, r, dut_val, gold_val, exp_0, exp_1, chain_en);
            $fatal(1);
        end
    endtask

    task automatic check(input bit chain_en_t);
        int amt0;
        int amt1;
        logic [EXP_WIDTH-1:0] emax;
        chain_en = chain_en_t;
        #1;
        emax = (exp_0 > exp_1) ? exp_0 : exp_1;
        amt0 = int'(emax) - int'(exp_0);
        amt1 = int'(emax) - int'(exp_1);
        if (h_exp !== emax || l_exp !== emax || u_exp !== emax) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("align_cell_bfp: exp_o mismatch: h %0d l %0d u %0d gold %0d (exp_0 %0d exp_1 %0d)",
                   h_exp, l_exp, u_exp, emax, exp_0, exp_1);
            $fatal(1);
        end
        for (int r = 0; r < SIZE_0; r++) begin
            check_row("H bundle 0", r, h_out_0[r], WIDTH'($signed(in_h0[r]) >>> amt0));
            check_row("U bundle 0", r, u_out_0[r], WIDTH'(in_h0[r] >> amt0));
            check_row("L bundle 0", r, l_out_0[r],
                      chain_en_t ? WIDTH'($signed({in_h0[r], in_l0[r]}) >>> amt0)
                                 : WIDTH'($signed(in_l0[r]) >>> amt0));
        end
        for (int r = 0; r < SIZE_1; r++) begin
            check_row("H bundle 1", r, h_out_1[r], WIDTH'($signed(in_h1[r]) >>> amt1));
            check_row("U bundle 1", r, u_out_1[r], WIDTH'(in_h1[r] >> amt1));
            check_row("L bundle 1", r, l_out_1[r],
                      chain_en_t ? WIDTH'($signed({in_h1[r], in_l1[r]}) >>> amt1)
                                 : WIDTH'($signed(in_l1[r]) >>> amt1));
        end
    endtask

    task automatic rand_vec();
        int e0v;
        int e1v;
        int delta;
        for (int r = 0; r < SIZE_0; r++) begin
            in_h0[r] = WIDTH'({$urandom, $urandom});
            in_l0[r] = WIDTH'({$urandom, $urandom});
        end
        for (int r = 0; r < SIZE_1; r++) begin
            in_h1[r] = WIDTH'({$urandom, $urandom});
            in_l1[r] = WIDTH'({$urandom, $urandom});
        end
        e0v = int'($urandom_range(0, E_TOP));
        case ($urandom_range(0, 9))
            0:       delta = 0;
            1:       delta = 1;
            2:       delta = WIDTH - 1;
            3:       delta = WIDTH;
            4:       delta = WIDTH + 1;
            5:       delta = 2 * WIDTH - 1;
            6:       delta = 2 * WIDTH;
            7:       delta = 2 * WIDTH + 1;
            8:       delta = int'($urandom_range(0, E_TOP));
            default: delta = int'($urandom_range(0, WIDTH));
        endcase
        if ($urandom_range(0, 1) == 1) begin
            delta = -delta;
        end
        e1v = e0v + delta;
        if (e1v < 0) begin
            e1v = 0;
        end
        if (e1v > E_TOP) begin
            e1v = E_TOP;
        end
        exp_0 = EXP_WIDTH'(e0v);
        exp_1 = EXP_WIDTH'(e1v);
    endtask

    task automatic set_vec(input logic [WIDTH-1:0] val_h,
                           input logic [WIDTH-1:0] val_l,
                           input logic [EXP_WIDTH-1:0] e0v,
                           input logic [EXP_WIDTH-1:0] e1v);
        for (int r = 0; r < SIZE_0; r++) begin
            in_h0[r] = val_h;
            in_l0[r] = val_l;
        end
        for (int r = 0; r < SIZE_1; r++) begin
            in_h1[r] = val_h;
            in_l1[r] = val_l;
        end
        exp_0 = e0v;
        exp_1 = e1v;
    endtask

    initial begin
        int deltas [0:6];
        deltas = '{1, WIDTH - 1, WIDTH, WIDTH + 1, 2 * WIDTH - 1, 2 * WIDTH, 2 * WIDTH + 1};
        $display("tb_align_cell_bfp: WIDTH=%0d SIZE_0=%0d SIZE_1=%0d EXP_WIDTH=%0d NUM_RAND=%0d",
                 WIDTH, SIZE_0, SIZE_1, EXP_WIDTH, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_align_cell_bfp);
`endif
        for (int n = 0; n < NUM_RAND; n++) begin
            rand_vec();
            check(1'b0);
            check(1'b1);
        end
        set_vec(MAX_POS, MIN_NEG, E_MID, E_MID);
        check(1'b0);
        check(1'b1);
        set_vec(MIN_NEG, MAX_POS, E_MIN, E_MAX);
        check(1'b0);
        check(1'b1);
        set_vec(MIN_NEG, MAX_POS, E_MAX, E_MIN);
        check(1'b0);
        check(1'b1);
        set_vec(ZERO, ALL_ONES, E_MIN, E_MAX);
        check(1'b0);
        check(1'b1);
        set_vec(ALL_ONES, ZERO, E_MAX, E_MIN);
        check(1'b0);
        check(1'b1);
        for (int d = 0; d < 7; d++) begin
            set_vec(MIN_NEG, MAX_POS, E_MID, EXP_WIDTH'(int'(E_MID) + deltas[d]));
            check(1'b0);
            check(1'b1);
            set_vec(MAX_POS, MIN_NEG, EXP_WIDTH'(int'(E_MID) + deltas[d]), E_MID);
            check(1'b0);
            check(1'b1);
        end
`ifdef VCD
        $dumpoff;
`endif
        $display("align_cell_bfp: all %0d random + corner vectors PASSED!", NUM_RAND);
        $finish;
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
