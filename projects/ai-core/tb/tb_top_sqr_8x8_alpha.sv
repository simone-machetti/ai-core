// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Testbench for top_sqr_8x8_alpha. Drives 16 a_i inputs through the
//   DUT and checks against the expected result, selected by IS_SQUARE:
//     IS_SQUARE = 1: out = sum_i(a[i]^2)
//     IS_SQUARE = 0: out = sum_i(a[i])
//   Runs 1000 random tests followed by corner cases (max-positive,
//   min-negative, mixed-sign, zero). Supports RTL and post-synthesis
//   simulation via POST_SYNTH define. Dumps activity.vcd for dynamic
//   power analysis.
//
// Parameters:
//   IS_PIPELINED - forwarded to DUT
//   IS_SQUARE    - 1 = squaring mode; 0 = accumulate mode
//   MAX_VAL_A    - max positive value for a inputs (0..2^(IN_WIDTH_A-1)-1, default = 2^(IN_WIDTH_A-1)-1)
//   DIST_TYPE    - 0 = uniform over [-MAX_VAL, +MAX_VAL], 1 = bimodal normal at ±MU_SCALE × MAX_VAL with std-dev SIGMA_SCALE × MAX_VAL, random sign per sample (default = 0)
//   MU_SCALE     - mean of the normal distribution as a fraction of MAX_VAL (default = 1.0/2.0)
//   SIGMA_SCALE  - std-dev of the normal distribution as a fraction of MAX_VAL (default = 1.0/6.0)
// -----------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off DECLFILENAME */

`timescale 1 ns/1 ps

module tb_top_sqr_8x8_alpha #(
    parameter bit  IS_PIPELINED = 1,
    parameter bit  IS_SQUARE    = 0,
    parameter int  MAX_VAL_A    = 127,
    parameter int  DIST_TYPE    = 0,
    parameter real MU_SCALE     = 1.0/2.0,
    parameter real SIGMA_SCALE  = 1.0/6.0
);
    localparam int IN_SIZE      = 16;
    localparam int IN_WIDTH_A   = 8;
    localparam int EXT_NUM      = 3;
    localparam int PP_WIDTH     = IS_SQUARE ? (2 * IN_WIDTH_A) : IN_WIDTH_A;
    localparam int CPR_EXT_BITS = 4;
    localparam int OUT_WIDTH    = PP_WIDTH + CPR_EXT_BITS + 16;

    real clk_p = `CLK_PERIOD_NS;

    logic                  clk;
    logic                  rst_n;
    logic                  is_signed [ 0:EXT_NUM-1];
    logic                  is_shift  [ 0:EXT_NUM-1];
    logic [IN_WIDTH_A-1:0] a         [ 0:IN_SIZE-1];
    logic [ OUT_WIDTH-1:0] out;

    logic [ OUT_WIDTH-1:0] exp;
    logic [IN_WIDTH_A-1:0] max_pos;
    logic [IN_WIDTH_A-1:0] min_neg;

`ifdef POST_SYNTH
    logic [IN_SIZE*IN_WIDTH_A-1:0] a_flat;
    logic [EXT_NUM-1:0]            is_signed_flat;
    logic [EXT_NUM-1:0]            is_shift_flat;

    always_comb begin
        for (int i = 0; i < IN_SIZE; i++) begin
            a_flat[i*IN_WIDTH_A +: IN_WIDTH_A] = a[i];
        end
        for (int i = 0; i < EXT_NUM; i++) begin
            is_signed_flat[i] = is_signed[i];
            is_shift_flat[i]  = is_shift[i];
        end
    end

    top_sqr_8x8_alpha top_sqr_8x8_alpha_i (
        .clk_i      (clk),
        .rst_ni     (rst_n),
        .is_signed_i(is_signed_flat),
        .is_shift_i (is_shift_flat),
        .a_i        (a_flat),
        .out_o      (out)
    );
`else
    top_sqr_8x8_alpha #(
        .IS_PIPELINED(IS_PIPELINED),
        .IS_SQUARE   (IS_SQUARE)
    ) top_sqr_8x8_alpha_i (
        .clk_i      (clk),
        .rst_ni     (rst_n),
        .is_signed_i(is_signed),
        .is_shift_i (is_shift),
        .a_i        (a),
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

    // -------------------------------------------------------------------------
    // Verification tasks
    // -------------------------------------------------------------------------
    task automatic run_and_check(
        input bit                           use_random,
        input logic signed [IN_WIDTH_A-1:0] a_fixed
    );
        logic signed [OUT_WIDTH-1:0] a_ext;
        logic signed [OUT_WIDTH-1:0] sqr_ext;

        begin
            exp = '0;

            for (int k = 0; k < EXT_NUM; k++) begin
                is_signed[k] = 1'b1;
                is_shift[k]  = 1'b0;
            end

            for (int i = 0; i < IN_SIZE; i++) begin
                if (use_random) begin
                    a[i] = gen_a();
                end else begin
                    a[i] = a_fixed;
                end

                a_ext   = OUT_WIDTH'($signed(a[i]));
                sqr_ext = OUT_WIDTH'(a_ext * a_ext);

                if (IS_SQUARE) begin
                    exp = OUT_WIDTH'($signed(exp)) + OUT_WIDTH'(sqr_ext);
                end else begin
                    exp = OUT_WIDTH'($signed(exp)) + OUT_WIDTH'(a_ext);
                end
            end

            if (IS_PIPELINED) begin
                repeat(3) @(posedge clk);
            end else begin
                repeat(2) @(posedge clk);
            end

            if (out !== exp) begin
                $dumpoff;
                $error("Error!\n");
                $fatal;
            end
        end

    endtask

    task automatic verify_with_random;
        begin
            for (int i = 0; i < 1000; i++) begin
                run_and_check(1'b1, '0);
            end
        end
    endtask

    task automatic verify_with_corner;
        logic [IN_WIDTH_A-1:0] mixed_pos;
        logic [IN_WIDTH_A-1:0] mixed_neg;
        begin
            max_pos   = IN_WIDTH_A'(MAX_VAL_A);
            min_neg   = IN_WIDTH_A'(-MAX_VAL_A);
            mixed_pos = IN_WIDTH_A'(max_pos >> 1);
            mixed_neg = IN_WIDTH_A'(min_neg | 8'h01);

            run_and_check(1'b0, max_pos);
            run_and_check(1'b0, min_neg);
            run_and_check(1'b0, mixed_pos);
            run_and_check(1'b0, mixed_neg);
            run_and_check(1'b0,        '0);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main control code
    // -------------------------------------------------------------------------
    initial begin
        $display("\nStarting verification...\n");

        $dumpfile("activity.vcd");
        $dumpvars(0, tb_top_sqr_8x8_alpha.top_sqr_8x8_alpha_i);

        reset_dut;

        verify_with_random;
        verify_with_corner;

        $dumpoff;

        $display("All tests PASSED!\n");
        $finish;
    end

endmodule
