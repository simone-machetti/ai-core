// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for align_bfp. Instantiates a signed and an
//   unsigned tree sharing the same stimulus and checks both against the flat
//   value-level golden: exp_o must equal the maximum of all input exponents,
//   and every row of every bundle must equal the input row right-shifted by
//   (max exponent - bundle exponent) - arithmetic for the signed tree,
//   logical for the unsigned one. Passing proves the cascaded per-level
//   shifts of the tree compose to the single flat shift. Exponents are drawn
//   as corner-biased deltas around a common base (with a dedicated all-equal
//   pass that must be bit-transparent, the pure-integer anchor, and a one-hot
//   max pattern that deep-flushes every other bundle); row corners use the
//   named constants.
//
// Parameters:
//   WIDTH     - row width
//   SIZE      - number of rows per bundle
//   NUM_EXP   - number of bundles/exponents
//   EXP_WIDTH - exponent width
//   NUM_RAND  - number of random vectors
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */
module tb_align_bfp #(
    parameter  int WIDTH     = 20,
    parameter  int SIZE      = 1,
    parameter  int NUM_EXP   = 8,
    parameter  int EXP_WIDTH = 8,
    parameter  int NUM_RAND  = 2000,
    localparam int E_TOP     = 2 ** EXP_WIDTH - 1,
    localparam int TOTAL     = NUM_EXP * SIZE
);

    localparam logic [    WIDTH-1:0] ZERO     = '0;
    localparam logic [    WIDTH-1:0] ALL_ONES = '1;
    localparam logic [    WIDTH-1:0] MAX_POS  = {1'b0, {(WIDTH-1){1'b1}}};
    localparam logic [    WIDTH-1:0] MIN_NEG  = {1'b1, {(WIDTH-1){1'b0}}};
    localparam logic [EXP_WIDTH-1:0] E_MIN    = '0;
    localparam logic [EXP_WIDTH-1:0] E_MAX    = '1;
    localparam logic [EXP_WIDTH-1:0] E_MID    = {1'b1, {(EXP_WIDTH-1){1'b0}}};

    logic [    WIDTH-1:0] in_s  [0:NUM_EXP-1][0:SIZE-1];
    logic [EXP_WIDTH-1:0] exp_s [0:NUM_EXP-1];

    logic [    WIDTH-1:0] s_out [0:TOTAL-1];
    logic [EXP_WIDTH-1:0] s_exp;
    logic [    WIDTH-1:0] u_out [0:TOTAL-1];
    logic [EXP_WIDTH-1:0] u_exp;

    align_bfp #(
        .WIDTH    (WIDTH),
        .SIZE     (SIZE),
        .NUM_EXP  (NUM_EXP),
        .EXP_WIDTH(EXP_WIDTH),
        .IS_SIGNED(1'b1)
    ) align_bfp_s_i (
        .in_i (in_s),
        .exp_i(exp_s),
        .out_o(s_out),
        .exp_o(s_exp)
    );

    align_bfp #(
        .WIDTH    (WIDTH),
        .SIZE     (SIZE),
        .NUM_EXP  (NUM_EXP),
        .EXP_WIDTH(EXP_WIDTH),
        .IS_SIGNED(1'b0)
    ) align_bfp_u_i (
        .in_i (in_s),
        .exp_i(exp_s),
        .out_o(u_out),
        .exp_o(u_exp)
    );

    task automatic check_row(input string tag, input int k, input int j,
                             input logic [WIDTH-1:0] dut_val,
                             input logic [WIDTH-1:0] gold_val);
        if (dut_val !== gold_val) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("align_bfp: %s bundle %0d row %0d: dut %h gold %h (exp %0d max %0d)",
                   tag, k, j, dut_val, gold_val, exp_s[k], s_exp);
            $fatal(1);
        end
    endtask

    task automatic check();
        int amt;
        logic [EXP_WIDTH-1:0] emax;
        #1;
        emax = '0;
        for (int k = 0; k < NUM_EXP; k++) begin
            if (exp_s[k] > emax) begin
                emax = exp_s[k];
            end
        end
        if (s_exp !== emax || u_exp !== emax) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("align_bfp: exp_o mismatch: s %0d u %0d gold %0d", s_exp, u_exp, emax);
            $fatal(1);
        end
        for (int k = 0; k < NUM_EXP; k++) begin
            amt = int'(emax) - int'(exp_s[k]);
            for (int j = 0; j < SIZE; j++) begin
                check_row("signed", k, j, s_out[k*SIZE+j], WIDTH'($signed(in_s[k][j]) >>> amt));
                check_row("unsigned", k, j, u_out[k*SIZE+j], WIDTH'(in_s[k][j] >> amt));
            end
        end
    endtask

    task automatic rand_rows();
        for (int k = 0; k < NUM_EXP; k++) begin
            for (int j = 0; j < SIZE; j++) begin
                in_s[k][j] = WIDTH'({$urandom, $urandom});
            end
        end
    endtask

    task automatic rand_vec();
        int base;
        int delta;
        int ev;
        rand_rows();
        base = int'($urandom_range(0, E_TOP));
        for (int k = 0; k < NUM_EXP; k++) begin
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
            ev = base + delta;
            if (ev < 0) begin
                ev = 0;
            end
            if (ev > E_TOP) begin
                ev = E_TOP;
            end
            exp_s[k] = EXP_WIDTH'(ev);
        end
    endtask

    task automatic set_vec(input logic [WIDTH-1:0] val, input logic [EXP_WIDTH-1:0] ev);
        for (int k = 0; k < NUM_EXP; k++) begin
            for (int j = 0; j < SIZE; j++) begin
                in_s[k][j] = val;
            end
            exp_s[k] = ev;
        end
    endtask

    initial begin
        $display("tb_align_bfp: WIDTH=%0d SIZE=%0d NUM_EXP=%0d EXP_WIDTH=%0d NUM_RAND=%0d",
                 WIDTH, SIZE, NUM_EXP, EXP_WIDTH, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_align_bfp);
`endif
        for (int n = 0; n < NUM_RAND; n++) begin
            rand_vec();
            check();
        end
        for (int n = 0; n < NUM_RAND / 10; n++) begin
            rand_rows();
            for (int k = 0; k < NUM_EXP; k++) begin
                exp_s[k] = E_MID;
            end
            check();
        end
        for (int m = 0; m < NUM_EXP; m++) begin
            rand_rows();
            for (int k = 0; k < NUM_EXP; k++) begin
                exp_s[k] = (k == m) ? E_MAX : E_MIN;
            end
            check();
        end
        set_vec(MIN_NEG, E_MID);
        check();
        set_vec(MAX_POS, E_MAX);
        check();
        set_vec(ALL_ONES, E_MIN);
        check();
        set_vec(ZERO, E_MAX);
        check();
`ifdef VCD
        $dumpoff;
`endif
        $display("align_bfp: all %0d random + corner vectors PASSED!", NUM_RAND);
        $finish;
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
