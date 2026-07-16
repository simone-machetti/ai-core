// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Per-mode constants for the square datapath reconstruction
//       out = 1/2 ( PE - alpha - beta + C ).
//   The accumulator is fully additive: it never subtracts. alpha and beta are
//   subtracted by one's-complementing their carry-save taps and *adding* them
//   (~a_sum + ~a_carry = -alpha - 2), and PE's complex-mode block negates are
//   likewise deferred. Every such deferral is a data-independent constant, all
//   folded here into C, so the accumulator is just a CPR + this constant. C is
//   the signed value the accumulator ADDS to the output - no subtract, no
//   carry-in injection.
//
//   A small combinational LUT addressed by the 4-bit mode, emitting TWO per-mode
//   constants because the complex modes need a different C on their two output
//   halves (see square_imp.md section 4 and the mode_10/11/12 sheets). C folds:
//     + C_real : the excess-8 centering constant (verified per mode). Real modes
//                and the Im(D) half of complex modes; Re(D)'s C_real is 0 (the
//                +re.re and -im.im centering constants cancel).
//     + 4      : subtracting alpha and beta via one's-complement defers -2 each
//                (two carry-save operands) -> +4 on EVERY output.
//     - 2N     : the comp_n block-negate deferral, on the negated Re(D) outputs
//                only (the negated im.im group lands in Re, whose C_real is 0).
//                Tree-weighted; only the hardware-negated modes 10/11 (2N = 34,
//                68). Mode 12 is software pre-negated (N = 0); real modes N = 0.
//
//     c_o     = C_real + 4               (positive / Im / real outputs)
//     c_neg_o = 0 + 4 - 2N               (negated Re outputs of complex modes)
//
//     mode | prec    | c_o = C_real+4    | c_neg_o = 4-2N (Re)
//     -----+---------+-------------------+--------------------
//      1   | R8R4    | 1 028             |  -
//      2   | R8R8    | 36 868            |  -
//      3   | R16R8   | 4 892 676         |  -
//      5   | R8R4    | 2 052             |  -
//      6   | R8R8    | 73 732            |  -
//      7   | R16R8   | 9 785 348         |  -
//      8   | R16R16  | 2 595 360 772     |  -
//      9   | R16R16  | 1 297 680 388     |  -
//     10   | C8C8    | 36 868 (Im)       | -30  (= 4 - 34)
//     11   | C8C8    | 73 732 (Im)       | -64  (= 4 - 68)
//     12   | C16C16  | 1 297 680 388 (Im)|  +4  (= 4 - 0)
//
//   The accumulator adds c_o on the positive (Im / real) outputs and c_neg_o on
//   the negated (Re) outputs; both are the final constant, added, never
//   subtracted. Invalid mode addresses return 0 on both.
//
// Parameters:
//   MODE_WIDTH - mode address width (4)
//   C_WIDTH    - positive-constant width (32, holds the widest C_real + 4)
//   CNEG_WIDTH - signed Re-constant width (8 bits hold -64..+4)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module const_sqr #(
    parameter int MODE_WIDTH = 4,
    parameter int C_WIDTH    = 32,
    parameter int CNEG_WIDTH = 8
)(
    input  logic        [MODE_WIDTH-1:0] mode_i,
    output logic        [   C_WIDTH-1:0] c_o,
    output logic signed [CNEG_WIDTH-1:0] c_neg_o
);

    always_comb begin
        c_neg_o = '0;
        unique case (mode_i)
            4'd1:    c_o = C_WIDTH'(32'd1028);
            4'd2:    c_o = C_WIDTH'(32'd36868);
            4'd3:    c_o = C_WIDTH'(32'd4892676);
            4'd5:    c_o = C_WIDTH'(32'd2052);
            4'd6:    c_o = C_WIDTH'(32'd73732);
            4'd7:    c_o = C_WIDTH'(32'd9785348);
            4'd8:    c_o = C_WIDTH'(32'd2595360772);
            4'd9:    c_o = C_WIDTH'(32'd1297680388);
            4'd10:   begin c_o = C_WIDTH'(32'd36868);      c_neg_o = -8'sd30; end
            4'd11:   begin c_o = C_WIDTH'(32'd73732);      c_neg_o = -8'sd64; end
            4'd12:   begin c_o = C_WIDTH'(32'd1297680388); c_neg_o =  8'sd4;  end
            default: c_o = '0;
        endcase
    end

endmodule
