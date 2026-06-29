// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Array of SIZE D flip-flops, each WIDTH bits wide, with active-low
//   asynchronous reset. Used as input and intermediate pipeline registers
//   throughout the PE datapath.
// -----------------------------------------------------------------------------

/* verilator lint_off UNOPTFLAT */

`timescale 1 ns/1 ps

module ff_n #(
    parameter int WIDTH = 8,
    parameter int SIZE  = 4
)(
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [WIDTH-1:0] d_i [0:SIZE-1],
    output logic [WIDTH-1:0] q_o [0:SIZE-1]
);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < SIZE; i++) begin
                q_o[i] <= '0;
            end
        end else begin
            q_o <= d_i;
        end
    end

endmodule
