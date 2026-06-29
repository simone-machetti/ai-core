// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Testbench for top_win_4x8_sc. Drives 64 (a, b) inputs through the DUT
//   and checks against the Winograd split-cell expected result, which combines
//   the Winograd pairing with B sub-lane decomposition (b_lo = B[3:0],
//   b_hi = B[7:4]):
//     out = sum_{i=0,2,...}[(a[i+1]+b_lo[i])*(a[i]+b_lo[i+1])
//                         + 16*(a[i+1]+b_hi[i])*(a[i]+b_hi[i+1])] + sum(acc)
//   Runs 1000 random tests followed by 5 corner cases. Supports RTL and
//   post-synthesis simulation via POST_SYNTH define. Dumps activity.vcd.
//
// Parameters:
//   IS_PIPELINED - forwarded to DUT (1 = 3-cycle latency, 0 = 2-cycle)
//   MULT_TYPE    - 0 = Radix-4 Booth, 1 = Radix-8 Booth
//   MAX_VAL_A    - max positive value for a inputs (0..2^(IN_WIDTH_A-1)-1, default = 2^(IN_WIDTH_A-1)-1)
//   MAX_VAL_B    - max positive value for b inputs (0..2^(IN_WIDTH_B-1)-1, default = 2^(IN_WIDTH_B-1)-1)
//   DIST_TYPE    - 0 = uniform over [-MAX_VAL, +MAX_VAL], 1 = bimodal normal at ±MU_SCALE × MAX_VAL with std-dev SIGMA_SCALE × MAX_VAL, random sign per sample (default = 0)
//   MU_SCALE     - mean of the normal distribution as a fraction of MAX_VAL (default = 1.0/2.0)
//   SIGMA_SCALE  - std-dev of the normal distribution as a fraction of MAX_VAL (default = 1.0/6.0)
// -----------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off DECLFILENAME */

`timescale 1 ns/1 ps

module tb_top_win_4x8_sc #(
    parameter bit  IS_PIPELINED = 1,
    parameter int  MULT_TYPE    = 0,
    parameter int  MAX_VAL_A    = 7,
    parameter int  MAX_VAL_B    = 127,
    parameter int  DIST_TYPE    = 0,
    parameter real MU_SCALE     = 1.0/2.0,
    parameter real SIGMA_SCALE  = 1.0/6.0
);
    localparam int IN_SIZE    = 64;
    localparam int IN_WIDTH_A = 4;
    localparam int IN_WIDTH_B = 8;
    localparam int ACC_SIZE   = 3;
    localparam int ACC_WIDTH  = 48;
    localparam int EXT_NUM    = 15;
    localparam int OUT_WIDTH  = ACC_WIDTH;
    localparam int ALPHA_LANES = 32;  // matches 4x8 alpha IN_SIZE (consistency w/ sqr_4x8_sc)

    real clk_p = `CLK_PERIOD_NS;

    logic                  clk;
    logic                  rst_n;
    logic [ ACC_WIDTH-1:0] acc       [0:ACC_SIZE-1];
    logic                  is_signed [ 0:EXT_NUM-1];
    logic                  is_shift  [ 0:EXT_NUM-1];
    logic [IN_WIDTH_A-1:0] a         [ 0:IN_SIZE-1];
    logic [IN_WIDTH_B-1:0] b         [ 0:IN_SIZE-1];
    logic [ OUT_WIDTH-1:0] out;

    logic [ ACC_WIDTH-1:0] exp;
    logic [IN_WIDTH_A-1:0] max_pos_0;
    logic [IN_WIDTH_A-1:0] min_neg_0;
    logic [IN_WIDTH_B-1:0] max_pos_1;
    logic [IN_WIDTH_B-1:0] min_neg_1;

`ifdef POST_SYNTH
    logic [IN_SIZE*IN_WIDTH_A-1:0] a_flat;
    logic [IN_SIZE*IN_WIDTH_B-1:0] b_flat;
    logic [ACC_SIZE*ACC_WIDTH-1:0] acc_flat;
    logic [EXT_NUM-1:0]            is_signed_flat;
    logic [EXT_NUM-1:0]            is_shift_flat;

    always_comb begin
        for (int i = 0; i < IN_SIZE; i++) begin
            a_flat[i*IN_WIDTH_A +: IN_WIDTH_A] = a[i];
            b_flat[i*IN_WIDTH_B +: IN_WIDTH_B] = b[i];
        end
        for (int i = 0; i < ACC_SIZE; i++)
            acc_flat[i*ACC_WIDTH +: ACC_WIDTH] = acc[i];
        for (int i = 0; i < EXT_NUM; i++) begin
            is_signed_flat[i] = is_signed[i];
            is_shift_flat[i]  = is_shift[i];
        end
    end

    top_win_4x8_sc top_win_4x8_sc_i (
        .clk_i      (clk),
        .rst_ni     (rst_n),
        .acc_i      (acc_flat),
        .is_signed_i(is_signed_flat),
        .is_shift_i (is_shift_flat),
        .a_i        (a_flat),
        .b_i        (b_flat),
        .out_o      (out)
    );
`else
    top_win_4x8_sc #(
        .IS_PIPELINED(IS_PIPELINED),
        .MULT_TYPE   (MULT_TYPE)
    ) top_win_4x8_sc_i (
        .clk_i      (clk),
        .rst_ni     (rst_n),
        .acc_i      (acc),
        .is_signed_i(is_signed),
        .is_shift_i (is_shift),
        .a_i        (a),
        .b_i        (b),
        .out_o      (out)
    );
`endif

    // -------------------------------------------------------------------------
    // Reset DUT
    // -------------------------------------------------------------------------
    task automatic reset_dut;
    begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    end
    endtask

    // -------------------------------------------------------------------------
    // Generate the clock
    // -------------------------------------------------------------------------
    initial clk = 1'b0;

    always begin
        clk = 1'b0;
        #(clk_p/2);
        clk = 1'b1;
        #(clk_p/2);
    end

    // -------------------------------------------------------------------------
    // Random input generation
    // -------------------------------------------------------------------------
    function automatic real normal_rand(real mu, real sigma);
        real u1, u2;
        u1 = (real'($urandom()) + 1.0) / 4294967297.0;
        u2 = real'($urandom()) / 4294967295.0;
        return mu + sigma * ($sqrt(-2.0 * $ln(u1)) * $cos(6.28318530717959 * u2));
    endfunction

    function automatic logic [IN_WIDTH_A-1:0] gen_a();
        real s;
        int  v;
        if (MAX_VAL_A == 0)
            return '0;
        if (DIST_TYPE == 0)
            return IN_WIDTH_A'($signed(int'($urandom_range(0, 2 * MAX_VAL_A)) - MAX_VAL_A));
        s = normal_rand(MU_SCALE    * real'(MAX_VAL_A),
                        SIGMA_SCALE * real'(MAX_VAL_A));
        v = int'($floor(s + 0.5));
        if (v < 0)                           v = 0;
        if (v > (1 << (IN_WIDTH_A - 1)) - 1) v = (1 << (IN_WIDTH_A - 1)) - 1;
        if ($urandom_range(0, 1) != 0)       v = -v;
        return IN_WIDTH_A'($signed(v));
    endfunction

    function automatic logic [IN_WIDTH_B-1:0] gen_b();
        real s;
        int  v;
        if (DIST_TYPE == 0)
            return IN_WIDTH_B'($signed(int'($urandom_range(0, 2 * MAX_VAL_B)) - MAX_VAL_B));
        s = normal_rand(MU_SCALE    * real'(MAX_VAL_B),
                        SIGMA_SCALE * real'(MAX_VAL_B));
        v = int'($floor(s + 0.5));
        if (v < 0)                           v = 0;
        if (v > (1 << (IN_WIDTH_B - 1)) - 1) v = (1 << (IN_WIDTH_B - 1)) - 1;
        if ($urandom_range(0, 1) != 0)       v = -v;
        return IN_WIDTH_B'($signed(v));
    endfunction

    // -------------------------------------------------------------------------
    // Verification tasks
    // -------------------------------------------------------------------------
    task automatic run_and_check(
        input bit                           use_random,
        input logic signed [IN_WIDTH_A-1:0] a0_fixed,
        input logic signed [IN_WIDTH_B-1:0] b0_fixed,
        input logic signed [IN_WIDTH_A-1:0] a1_fixed,
        input logic signed [IN_WIDTH_B-1:0] b1_fixed
    );
        logic signed [OUT_WIDTH-1:0] a0_ext, a1_ext;
        logic signed [OUT_WIDTH-1:0] b0_lo_ext, b1_lo_ext;
        logic signed [OUT_WIDTH-1:0] b0_hi_ext, b1_hi_ext;
        logic signed [OUT_WIDTH-1:0] p_lo, p_hi;

        logic        [3:0] b0_lo, b1_lo;
        logic signed [3:0] b0_hi, b1_hi;
        begin
            exp    = '0;
            acc[0] = ACC_WIDTH'($urandom_range(0, (1 << ACC_WIDTH) - 1));
            acc[1] = ACC_WIDTH'($urandom_range(0, ALPHA_LANES * MAX_VAL_A * MAX_VAL_A));
            acc[2] = ACC_WIDTH'($signed(int'($urandom_range(0, 2 * ALPHA_LANES * MAX_VAL_A)) - ALPHA_LANES * MAX_VAL_A));

            for (int k = 0; k < EXT_NUM; k ++) begin
                is_signed[k] = 1'b1;
                is_shift[k]  = 1'b0;
            end

            for (int i = 0; i < IN_SIZE; i = i + 2) begin
                if (use_random) begin
                    a[i]   = gen_a();
                    b[i]   = gen_b();
                    a[i+1] = gen_a();
                    b[i+1] = gen_b();
                end else begin
                    a[i]   = a0_fixed;
                    b[i]   = b0_fixed;
                    a[i+1] = a1_fixed;
                    b[i+1] = b1_fixed;
                end

                a0_ext = OUT_WIDTH'($signed(a[i]));
                a1_ext = OUT_WIDTH'($signed(a[i+1]));

                b0_lo = b[i][3:0];
                b1_lo = b[i+1][3:0];
                b0_hi = b[i][7:4];
                b1_hi = b[i+1][7:4];

                b0_lo_ext = OUT_WIDTH'($unsigned(b0_lo));
                b1_lo_ext = OUT_WIDTH'($unsigned(b1_lo));

                b0_hi_ext = OUT_WIDTH'($signed(b0_hi));
                b1_hi_ext = OUT_WIDTH'($signed(b1_hi));

                p_lo = (a1_ext + b0_lo_ext) * (a0_ext + b1_lo_ext);
                p_hi = (a1_ext + b0_hi_ext) * (a0_ext + b1_hi_ext);

                exp = OUT_WIDTH'($signed(exp)) + OUT_WIDTH'($signed(p_lo + (p_hi <<< 4)));
            end

            if (IS_PIPELINED) begin
                repeat(3) @(posedge clk);
            end else begin
                repeat(2) @(posedge clk);
            end

            if (out !== OUT_WIDTH'($signed(exp) + $signed(acc[0]) + $signed(acc[1]) + $signed(acc[2]))) begin
                $error("Error!\n");
                $fatal;
            end
        end
    endtask

    task automatic verify_with_random;
        begin
            for (int i = 0; i < 1000; i++) begin
                run_and_check(1'b1, '0, '0, '0, '0);
            end
        end
    endtask

    task automatic verify_with_corner;
        begin
            max_pos_0 = IN_WIDTH_A'(MAX_VAL_A);
            min_neg_0 = IN_WIDTH_A'(-MAX_VAL_A);
            max_pos_1 = IN_WIDTH_B'(MAX_VAL_B);
            min_neg_1 = IN_WIDTH_B'(-MAX_VAL_B);

            run_and_check(1'b0, max_pos_0, max_pos_1, max_pos_0, max_pos_1);
            run_and_check(1'b0, min_neg_0, min_neg_1, min_neg_0, min_neg_1);
            run_and_check(1'b0, max_pos_0, min_neg_1, max_pos_0, min_neg_1);
            run_and_check(1'b0, min_neg_0, max_pos_1, min_neg_0, max_pos_1);
            run_and_check(1'b0,        '0,        '0,        '0,        '0);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main control code
    // -------------------------------------------------------------------------
    initial begin
        $display("\nStarting verification...\n");

        $dumpfile("activity.vcd");
        $dumpvars(0, tb_top_win_4x8_sc.top_win_4x8_sc_i);

        reset_dut;

        verify_with_random;
        verify_with_corner;

        $dumpoff;

        $display("All tests PASSED!\n");
        $finish;
    end

endmodule
