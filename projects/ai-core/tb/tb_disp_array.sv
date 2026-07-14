// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Self-checking testbench for disp_array. For each of the 11 operating modes it
//   drives the mode's dispatch control vector (block selects + B-gate ops, taken
//   from doc/formulas/modes.xlsx), pushes NUM_RAND random 256-bit operands plus a
//   directed ramp vector through the input registers, and checks every DP8 output
//   against a golden router model (block-select, high/low B split, per-int4
//   gate). Reports a fatal error on any mismatch. Dumps activity.vcd.
//
// Parameters:
//   NUM_RAND - number of random operand vectors per mode
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_disp_array #(
    parameter int NUM_RAND = 500
);

    localparam int NUM_BLK      = 4;
    localparam int BLK_WIDTH    = 64;
    localparam int NUM_PAIR     = 8;
    localparam int NUM_DP8      = 16;
    localparam int SEL_WIDTH    = 2;
    localparam int A_DP8_WIDTH  = 64;
    localparam int B_DP8_WIDTH  = 32;
    localparam int B_ELEM_WIDTH = 4;
    localparam int NUM_B_ELEM   = 8;
    localparam int OP_WIDTH     = 2;
    localparam int NUM_MODE     = 11;

    localparam int MODE_NUM [0:NUM_MODE-1] = '{1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12};

    localparam logic [1:0] SEL_A [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},  // mode 1
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},  // mode 2
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},  // mode 3
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},  // mode 5
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 6
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},  // mode 7
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},  // mode 8
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},  // mode 9
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},  // mode 10
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},  // mode 11
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd0, 2'd1, 2'd1}   // mode 12
    };

    localparam logic [1:0] SEL_B [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},  // mode 1
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},  // mode 2
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd0, 2'd0, 2'd1, 2'd1},  // mode 3
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd1, 2'd2, 2'd3},  // mode 5
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 6
        '{2'd0, 2'd0, 2'd1, 2'd1, 2'd2, 2'd2, 2'd3, 2'd3},  // mode 7
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},  // mode 8
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3},  // mode 9
        '{2'd0, 2'd1, 2'd1, 2'd0, 2'd2, 2'd3, 2'd3, 2'd2},  // mode 10
        '{2'd0, 2'd1, 2'd2, 2'd3, 2'd1, 2'd0, 2'd3, 2'd2},  // mode 11
        '{2'd0, 2'd1, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3}   // mode 12
    };

    localparam logic [1:0] CTR_L [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 1
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 2
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 3
        '{2'd1, 2'd1, 2'd1, 2'd1, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 5
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},  // mode 6
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 7
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 8
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 9
        '{2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd2, 2'd0, 2'd0},  // mode 10
        '{2'd0, 2'd2, 2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 11
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0}   // mode 12
    };

    localparam logic [1:0] CTR_H [0:NUM_MODE-1][0:NUM_PAIR-1] = '{
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 1
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 2
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 3
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},  // mode 5
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd1, 2'd1, 2'd1, 2'd1},  // mode 6
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 7
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 8
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 9
        '{2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd2, 2'd0, 2'd0},  // mode 10
        '{2'd0, 2'd2, 2'd0, 2'd2, 2'd0, 2'd0, 2'd0, 2'd0},  // mode 11
        '{2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0, 2'd0}   // mode 12
    };

    logic                         clk_i;
    logic                         rst_ni;
    logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_a;
    logic [NUM_BLK*BLK_WIDTH-1:0] pe_in_b;
    logic [       SEL_WIDTH-1:0]  sel_a [0:NUM_PAIR-1];
    logic [       SEL_WIDTH-1:0]  sel_b [0:NUM_PAIR-1];
    logic [        OP_WIDTH-1:0]  ctr_l [0:NUM_PAIR-1];
    logic [        OP_WIDTH-1:0]  ctr_h [0:NUM_PAIR-1];
    logic [     A_DP8_WIDTH-1:0]  a_dp8 [0:NUM_DP8-1];
    logic [     B_DP8_WIDTH-1:0]  b_dp8 [0:NUM_DP8-1];

    disp_array_a disp_array_a_i (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .pe_in_a_i(pe_in_a),
        .sel_a_i  (sel_a),
        .a_dp8_o  (a_dp8)
    );

    disp_array_b disp_array_b_i (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .pe_in_b_i(pe_in_b),
        .sel_b_i  (sel_b),
        .ctr_l_i  (ctr_l),
        .ctr_h_i  (ctr_h),
        .b_dp8_o  (b_dp8)
    );

    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    function automatic logic [B_DP8_WIDTH-1:0] gate32(input logic [B_DP8_WIDTH-1:0] x, input logic [OP_WIDTH-1:0] op);
        logic [B_DP8_WIDTH-1:0] y;
        y = x;
        case (op)
            2'd1:    y = '0;
            2'd2:    for (int e = 0; e < NUM_B_ELEM; e++) y[e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = (~x[e*B_ELEM_WIDTH +: B_ELEM_WIDTH]) + 4'd1;
            default: y = x;
        endcase
        return y;
    endfunction

    task automatic set_controls(input int mi);
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = SEL_A[mi][p];
            sel_b[p] = SEL_B[mi][p];
            ctr_l[p] = CTR_L[mi][p];
            ctr_h[p] = CTR_H[mi][p];
        end
    endtask

    task automatic check(input int mi);
        logic [   BLK_WIDTH-1:0] a_sel;
        logic [   BLK_WIDTH-1:0] b_sel;
        logic [ A_DP8_WIDTH-1:0] a_exp [0:NUM_DP8-1];
        logic [ B_DP8_WIDTH-1:0] b_exp [0:NUM_DP8-1];
        int oa, ob;
        for (int p = 0; p < NUM_PAIR; p++) begin
            oa    = int'(SEL_A[mi][p]) * BLK_WIDTH;
            ob    = int'(SEL_B[mi][p]) * BLK_WIDTH;
            a_sel = pe_in_a[oa +: BLK_WIDTH];
            b_sel = pe_in_b[ob +: BLK_WIDTH];
            a_exp[2*p+0] = a_sel;
            a_exp[2*p+1] = a_sel;
            b_exp[2*p+0] = gate32(b_sel[BLK_WIDTH-1:B_DP8_WIDTH], CTR_H[mi][p]);
            b_exp[2*p+1] = gate32(b_sel[B_DP8_WIDTH-1:0],        CTR_L[mi][p]);
        end
        for (int i = 0; i < NUM_DP8; i++) begin
            if (a_dp8[i] !== a_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("A MISMATCH mode=%0d dp8=%0d exp=%h got=%h", MODE_NUM[mi], i, a_exp[i], a_dp8[i]);
                $fatal;
            end
            if (b_dp8[i] !== b_exp[i]) begin
`ifdef VCD
                $dumpoff;
`endif
                $error("B MISMATCH mode=%0d dp8=%0d exp=%h got=%h", MODE_NUM[mi], i, b_exp[i], b_dp8[i]);
                $fatal;
            end
        end
    endtask

    task automatic rand_vec;
        for (int w = 0; w < NUM_BLK*BLK_WIDTH/32; w++) begin
            pe_in_a[w*32 +: 32] = $urandom;
            pe_in_b[w*32 +: 32] = $urandom;
        end
    endtask

    task automatic ramp_vec;
        for (int by = 0; by < NUM_BLK*BLK_WIDTH/8;  by++) pe_in_a[by*8 +: 8] = by[7:0];
        for (int ni = 0; ni < NUM_BLK*BLK_WIDTH/4;  ni++) pe_in_b[ni*4 +: 4] = ni[3:0];
    endtask

    initial begin
        $display("\nStarting disp_array verification (%0d modes x (%0d random + ramp))...\n", NUM_MODE, NUM_RAND);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, tb_disp_array);
`endif

        rst_ni  = 1'b0;
        pe_in_a = '0;
        pe_in_b = '0;
        for (int p = 0; p < NUM_PAIR; p++) begin
            sel_a[p] = '0; sel_b[p] = '0; ctr_l[p] = '0; ctr_h[p] = '0;
        end
        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;

        for (int mi = 0; mi < NUM_MODE; mi++) begin
            set_controls(mi);
            for (int t = 0; t < NUM_RAND; t++) begin
                rand_vec;
                @(posedge clk_i);
                #1;
                check(mi);
            end
            ramp_vec;
            @(posedge clk_i);
            #1;
            check(mi);
            $display("  mode %0d: PASS", MODE_NUM[mi]);
        end

`ifdef VCD
        $dumpoff;
`endif
        $display("\ndisp_array: all %0d modes x (%0d random + ramp) tests PASSED!\n", NUM_MODE, NUM_RAND);
        $finish;
    end

endmodule
