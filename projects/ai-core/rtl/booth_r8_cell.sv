// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Radix-8 Booth encoder cell. Maps a 4-bit selector (sel_i) derived from
//   three consecutive bits of multiplier A plus a 1-bit overlap onto one of
//   nine operations on multiplicand B: {0, ±B, ±2B, ±3B, ±4B}.
//   Output partial product is IN_WIDTH + 3 bits wide to accommodate the 4B
//   case without overflow.
//
// Parameters:
//   IN_WIDTH  - bit width of the multiplicand (B)
//   IS_SIGNED - 1 = signed B (sign-extended before shifting); 0 = unsigned
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module booth_r8_cell #(
    parameter int IN_WIDTH  = 16,
    parameter bit IS_SIGNED = 1,

    localparam int OUT_WIDTH = IN_WIDTH + 3
)(
    input  logic [ IN_WIDTH-1:0] mult_i,
    input  logic [          3:0] sel_i,
    output logic [OUT_WIDTH-1:0] pp_o
);

    logic [OUT_WIDTH-1:0] m_ext;

    assign m_ext = { {3{IS_SIGNED ? mult_i[IN_WIDTH-1] : 1'b0}}, mult_i};

    always_comb begin
        unique case (sel_i)
            4'b0000:  pp_o = '0;
            4'b1111:  pp_o = '0;
            4'b0001:  pp_o = m_ext;
            4'b0010:  pp_o = m_ext;
            4'b0011:  pp_o = m_ext <<< 1;
            4'b0100:  pp_o = m_ext <<< 1;
            4'b0101:  pp_o = (m_ext <<< 1) + m_ext;
            4'b0110:  pp_o = (m_ext <<< 1) + m_ext;
            4'b0111:  pp_o = m_ext <<< 2;
            4'b1000:  pp_o = -(m_ext <<< 2);
            4'b1001:  pp_o = -((m_ext <<< 1) + m_ext);
            4'b1010:  pp_o = -((m_ext <<< 1) + m_ext);
            4'b1011:  pp_o = -(m_ext <<< 1);
            4'b1100:  pp_o = -(m_ext <<< 1);
            4'b1101:  pp_o = -m_ext;
            4'b1110:  pp_o = -m_ext;
            default:  pp_o = '0;
        endcase
    end

endmodule
