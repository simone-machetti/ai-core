// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Radix-4 Booth encoder cell. Maps a 3-bit selector (sel_i), derived from two
//   consecutive multiplier bits plus a 1-bit overlap, onto one of the operations
//   {0, +B, +2B, -2B, -B} on the multiplicand mult_i, producing one partial
//   product. The output is IN_WIDTH + 2 bits wide to hold the 2B case. The
//   multiplicand is first extended by two bits: sign-extended when is_signed_i,
//   otherwise zero-extended; is_signed_i is a runtime signal so signedness can
//   change with the operating mode.
//
// Parameters:
//   IN_WIDTH - bit width of the multiplicand (mult_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module booth_r4_cell #(
    parameter int IN_WIDTH = 16,

    localparam int OUT_WIDTH = IN_WIDTH + 2
)(
    input  logic [ IN_WIDTH-1:0] mult_i,
    input  logic [          2:0] sel_i,
    input  logic                 is_signed_i,
    output logic [OUT_WIDTH-1:0] pp_o
);

    logic [OUT_WIDTH-1:0] m_ext;

    assign m_ext = {{2{is_signed_i ? mult_i[IN_WIDTH-1] : 1'b0}}, mult_i};

    always_comb begin
        case (sel_i)
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
