// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   NR4SD+ partial-product cell - the sibling of booth_r4_cell. Maps a 2-bit
//   NR4SD+ digit code onto one of the operations {0, +A, +2A, -A} on the
//   multiplicand mult_i, producing one partial product. The output is
//   IN_WIDTH + 2 bits wide to hold the 2A case. The multiplicand is first
//   extended by two bits: sign-extended when is_signed_i, otherwise
//   zero-extended; is_signed_i is a runtime signal so signedness can change with
//   the operating mode.
//
//   Code map (see nr4sd_r4):
//     00 -> 0    01 -> +A    10 -> +2A    11 -> -A
//
//   Note -2A is ABSENT: the NR4SD+ digit set is {-1,0,+1,+2}, so the shift and
//   the negation are mutually exclusive and the cell never has to build a
//   shifted-AND-inverted multiple. That is one branch fewer than booth_r4_cell,
//   whose {-2,-1,0,+1,+2} needs both -A and -2A.
//
//   Written as a case on the code rather than as a select over four
//   pre-materialized multiples: the specialized shift/negate structure
//   synthesizes materially smaller than a generic 4:1 mux over four 10-bit
//   words. Measured on dp_8_nr4sd_bfp: 211.13 um^2 with mux_n against 191.28
//   with this cell, i.e. the generic mux gave away the whole benefit of hoisting
//   the encoder and then some (dp_8 itself is 202.41).
//
// Parameters:
//   IN_WIDTH - bit width of the multiplicand (mult_i)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module nr4sd_r4_cell #(
    parameter int IN_WIDTH = 8,

    localparam int OUT_WIDTH  = IN_WIDTH + 2,
    localparam int CODE_WIDTH = 2
)(
    input  logic [  IN_WIDTH-1:0] mult_i,
    input  logic [CODE_WIDTH-1:0] code_i,
    input  logic                  is_signed_i,
    output logic [ OUT_WIDTH-1:0] pp_o
);

    logic [OUT_WIDTH-1:0] m_ext;

    assign m_ext = {{2{is_signed_i ? mult_i[IN_WIDTH-1] : 1'b0}}, mult_i};

    always_comb begin
        case (code_i)
            2'b01:   pp_o = m_ext;
            2'b10:   pp_o = m_ext <<< 1;
            2'b11:   pp_o = -m_ext;
            default: pp_o = '0;
        endcase
    end

endmodule
