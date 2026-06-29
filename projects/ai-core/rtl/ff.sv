// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   WIDTH-bit D flip-flop with active-low asynchronous reset.
//   Resets to zero on rst_ni de-assertion; captures d_i on rising clk_i edge.
// -----------------------------------------------------------------------------

/* verilator lint_off UNOPTFLAT */

`timescale 1 ns/1 ps

module ff #(
    parameter int WIDTH = 8
)(
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [WIDTH-1:0] d_i,
    output logic [WIDTH-1:0] q_o
);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            q_o <= '0;
        end else begin
            q_o <= d_i;
        end
    end

endmodule
