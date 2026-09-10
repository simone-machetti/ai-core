// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Hybrid NR4SD+ / Booth radix-4 recoder - the ENCB cell of
//   disp_array_b_nr4sd_bfp, one per B nibble. Recodes b_i into NUM_PAIR radix-4
//   digits - TWO for a 4-bit nibble - with no correction digit:
//
//     - the low pairs (j < NUM_PAIR-1) are NR4SD+ digits from the NON-REDUNDANT
//       set {-1, 0, +1, +2}, emitted as CODE_WIDTH = 2 bits each
//       (00 -> 0, 01 -> +1, 10 -> +2, 11 -> -1) and chained by a carry that ENTERS
//       the nibble through c_in_i:
//         s = 2*b_hi + b_lo + c  in [0,4]   ->   s = 4*c_out + digit
//         code[0] = b_lo ^ c
//         code[1] = b_hi ^ (b_lo & c)
//         c_out   = b_hi & (b_lo | c)
//     - the top pair is a Booth radix-4 digit from {-2, -1, 0, +1, +2}, emitted as
//       the 3-bit window {b_hi, b_lo, c} that booth_r4_cell decodes directly:
//         digit = -2*b_hi + b_lo + c
//       i.e. the pair read as SIGNED plus the carry from the pair below. No logic:
//       the window is wiring.
//
//   With the low pair's identity s = digit + 4*c_out the nibble recodes exactly to
//
//     sum_j(digit_j * 4^j) = signed(b_i) + c_in_i
//
//   and 4*[-2,+2] + [-1,+2] = [-9, +10] covers every int4 plus the +1. That is what
//   the mix is for: two NR4SD+ digits span only [-5, +10] and miss -8..-6 (the
//   values that forced NR4SD+'s third digit), two Booth digits would do it but at
//   3 bits each. Booth at the top only costs 5 bits per nibble instead of 6 and
//   confines the -2A multiple to one cell per lane.
//
//   The carry-in is the cross-nibble link of the 2-PP scheme. A nibble that is a
//   LOWER slice of a wider element is read as signed too, which is 16*b3 too
//   small; the nibble above repays it by taking c_in_i = b3 of the slice below.
//   The top nibble of an element, a whole int4 and an idle lane take c_in_i = 0.
//   The dispatcher owns that wiring (disp_array_b_nr4sd_bfp).
//
//   Purely combinational. Both zero codes are all-zero (NR4SD 00, Booth window
//   000), so an all-zero encoded bus is the zero multiplier - what lets
//   pe_nr4sd_bfp AND-mask the bus to quiet a gated lane.
//
// Parameters:
//   IN_WIDTH_B - bit width of the nibble b_i (even, at least 4)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module nr4sd_r4 #(
    parameter int IN_WIDTH_B = 4,

    localparam int NUM_PAIR    = IN_WIDTH_B / 2,
    localparam int CODE_WIDTH  = 2,
    localparam int SEL_WIDTH   = 3,
    localparam int NR4SD_WIDTH = (NUM_PAIR - 1) * CODE_WIDTH
)(
    input  logic [ IN_WIDTH_B-1:0] b_i,
    input  logic                   c_in_i,
    output logic [NR4SD_WIDTH-1:0] b_nr4sd_o,
    output logic [  SEL_WIDTH-1:0] b_booth_o
);

    logic [NUM_PAIR-1:0] carry;

    assign carry[0] = c_in_i;

    genvar j;
    generate
        for (j = 0; j < NUM_PAIR - 1; j++) begin : gen_nr4sd
            logic b_hi;
            logic b_lo;
            assign b_hi = b_i[2*j+1];
            assign b_lo = b_i[2*j];
            assign b_nr4sd_o[j*CODE_WIDTH]   = b_lo ^ carry[j];
            assign b_nr4sd_o[j*CODE_WIDTH+1] = b_hi ^ (b_lo & carry[j]);
            assign carry[j+1]                = b_hi & (b_lo | carry[j]);
        end
    endgenerate

    assign b_booth_o = {b_i[IN_WIDTH_B-1], b_i[IN_WIDTH_B-2], carry[NUM_PAIR-1]};

endmodule
