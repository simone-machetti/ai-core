// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Radix-4 Booth encoder cell. Maps a 3-bit selector (sel_i) derived from
//   two consecutive bits of multiplier A plus a 1-bit overlap onto one of
//   seven operations on multiplicand B: {0, +B, +2B, -2B, -B}.
//   Output partial product is IN_WIDTH + 2 bits wide to accommodate the 2B
//   case without overflow.
//
// Parameters:
//   IN_WIDTH  - bit width of the multiplicand (B)
//   IS_SIGNED - 1 = signed B (sign-extended before shifting); 0 = unsigned
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module booth_r4_cell #(
    parameter int IN_WIDTH  = 16,
    parameter bit IS_SIGNED = 1,

    localparam int OUT_WIDTH = IN_WIDTH + 2
)(
    input  logic [ IN_WIDTH-1:0] mult_i,
    input  logic [          2:0] sel_i,
    output logic [OUT_WIDTH-1:0] pp_o
);

    logic [OUT_WIDTH-1:0] m_ext;

    assign m_ext = {{2{IS_SIGNED ? mult_i[IN_WIDTH-1] : 1'b0}}, mult_i};

    always_comb begin
        unique case (sel_i)
            3'b000:  pp_o = '0;
            3'b111:  pp_o = '0;
            3'b001:  pp_o = m_ext;
            3'b010:  pp_o = m_ext;
            3'b011:  pp_o = m_ext <<< 1;
            3'b100:  pp_o = -(m_ext <<< 1);
            3'b101:  pp_o = -m_ext;
            3'b110:  pp_o = -m_ext;
            default: pp_o = '0;
        endcase
    end

endmodule
