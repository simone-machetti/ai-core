// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Integrated clock-gating cell. Passes clk_i through to clk_o while enabled
//   and holds clk_o low while disabled, so a downstream block can be frozen
//   without stopping the free-running clock. en_i is captured by a latch that
//   is transparent while clk_i is low, so a change on en_i part-way through a
//   cycle cannot chop the clock: clk_o = clk_i & latched(en_i), glitch-free.
//
//   Two implementations, selected by SYNTHESIS (defined by the synthesis
//   frontend, not by the simulator):
//     - synthesis : the ASAP7 ICG standard cell, so the clock gate reaches the
//                   netlist as one characterized cell that clock-tree synthesis
//                   recognizes as a clock gate. SE (scan enable) is tied off.
//     - simulation: the behavioural model above, which keeps the RTL portable
//                   and technology independent.
//   Both describe the same function; only the implementation differs.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module icg (
    input  logic clk_i,
    input  logic en_i,
    output logic clk_o
);

`ifdef SYNTHESIS

    ICGx1_ASAP7_75t_R icg_cell_i (
        .CLK (clk_i),
        .ENA (en_i),
        .SE  (1'b0),
        .GCLK(clk_o)
    );

`else

    logic clk_en;

    always_latch begin
        if (clk_i == 1'b0) begin
            clk_en = en_i;
        end
    end

    assign clk_o = clk_i & clk_en;

`endif

endmodule
