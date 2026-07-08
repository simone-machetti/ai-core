// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Integrated clock-gating cell. Passes clk_i through to clk_o while enabled
//   and holds clk_o low while disabled, so a downstream block can be frozen
//   without stopping the free-running clock. en_i is captured by a latch that
//   is transparent while clk_i is low, so a change on en_i part-way through a
//   cycle cannot chop the clock: clk_o = clk_i & latched(en_i), glitch-free.
//   Behavioural model of the standard-cell ICG used for per-block clock gating.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module icg (
    input  logic clk_i,
    input  logic en_i,
    output logic clk_o
);

    logic clk_en;

    always_latch begin
        if (clk_i == 1'b0) begin
            clk_en = en_i;
        end
    end

    assign clk_o = clk_i & clk_en;

endmodule
