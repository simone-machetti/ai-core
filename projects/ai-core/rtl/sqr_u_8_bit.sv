// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   Unsigned 8-bit squarer. Computes out_o = in_i^2 using a partial-product
//   compression tree that exploits squarer symmetry: diagonal terms a[i]^2 = a[i]
//   land at bit 2*i, and each unique off-diagonal product a[i]&a[j] (i<j) is
//   placed at bit i+j+1 (the factor-of-2 from symmetry). The 28 AND gates feed
//   a Wallace tree (21 FAs + 7 HAs) that reduces all columns to single bits with
//   no final carry-propagate adder.
//   Output is 16 bits wide (2 * 8 bits).
// -----------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */

`timescale 1 ns/1 ps

module sqr_u_8_bit (
    input  logic [7:0]  in_i,
    output logic [15:0] out_o
);

    logic a0, a1, a2, a3, a4, a5, a6, a7;
    assign {a7, a6, a5, a4, a3, a2, a1, a0} = in_i;

    // -------------------------------------------------------------------------
    // 28 off-diagonal partial products  p[i][j] = a[i] & a[j],  i < j
    // -------------------------------------------------------------------------
    logic p01, p02, p03, p04, p05, p06, p07;
    logic p12, p13, p14, p15, p16, p17;
    logic p23, p24, p25, p26, p27;
    logic p34, p35, p36, p37;
    logic p45, p46, p47;
    logic p56, p57;
    logic p67;

    assign p01 = a0 & a1;  assign p02 = a0 & a2;  assign p03 = a0 & a3;
    assign p04 = a0 & a4;  assign p05 = a0 & a5;  assign p06 = a0 & a6;
    assign p07 = a0 & a7;
    assign p12 = a1 & a2;  assign p13 = a1 & a3;  assign p14 = a1 & a4;
    assign p15 = a1 & a5;  assign p16 = a1 & a6;  assign p17 = a1 & a7;
    assign p23 = a2 & a3;  assign p24 = a2 & a4;  assign p25 = a2 & a5;
    assign p26 = a2 & a6;  assign p27 = a2 & a7;
    assign p34 = a3 & a4;  assign p35 = a3 & a5;  assign p36 = a3 & a6;
    assign p37 = a3 & a7;
    assign p45 = a4 & a5;  assign p46 = a4 & a6;  assign p47 = a4 & a7;
    assign p56 = a5 & a6;  assign p57 = a5 & a7;
    assign p67 = a6 & a7;

    // -------------------------------------------------------------------------
    // Compression tree
    //
    // Initial column occupancy (diagonal terms a[i] at bit 2i; off-diagonal
    // terms p[i][j] at bit i+j+1):
    //   bit  0: {a0}
    //   bit  1: {}
    //   bit  2: {a1, p01}
    //   bit  3: {p02}
    //   bit  4: {a2, p03, p12}
    //   bit  5: {p04, p13}
    //   bit  6: {a3, p05, p14, p23}
    //   bit  7: {p06, p15, p24}
    //   bit  8: {a4, p07, p16, p25, p34}
    //   bit  9: {p17, p26, p35}
    //   bit 10: {a5, p27, p36, p45}
    //   bit 11: {p37, p46}
    //   bit 12: {a6, p47, p56}
    //   bit 13: {p57}
    //   bit 14: {a7, p67}
    //   bit 15: {}
    // -------------------------------------------------------------------------

    // --- bit 2: HA(a1, p01) ---
    logic s2, c2;
    assign s2 = a1 ^ p01;
    assign c2 = a1 & p01;                                        // → bit 3

    // --- bit 3: HA(p02, c2) ---
    logic s3, c3;
    assign s3 = p02 ^ c2;
    assign c3 = p02 & c2;                                        // → bit 4

    // --- bit 4: FA(a2, p03, p12), HA(fa_s, c3) ---
    logic s4a, c4a, s4, c4;
    assign s4a = a2  ^ p03 ^ p12;
    assign c4a = (a2  & p03) | (p03 & p12) | (a2  & p12);        // → bit 5
    assign s4  = s4a ^ c3;
    assign c4  = s4a & c3;                                       // → bit 5

    // --- bit 5: FA(p04, p13, c4a), HA(fa_s, c4) ---
    logic s5a, c5a, s5, c5;
    assign s5a = p04 ^ p13 ^ c4a;
    assign c5a = (p04 & p13) | (p13 & c4a) | (p04 & c4a);        // → bit 6
    assign s5  = s5a ^ c4;
    assign c5  = s5a & c4;                                       // → bit 6

    // --- bit 6: FA(a3, p05, p14), FA(p23, c5a, c5), HA(fa_s_a, fa_s_b) ---
    logic s6a, c6a, s6b, c6b, s6, c6;
    assign s6a = a3  ^ p05 ^ p14;
    assign c6a = (a3  & p05) | (p05 & p14) | (a3  & p14);        // → bit 7
    assign s6b = p23 ^ c5a ^ c5;
    assign c6b = (p23 & c5a) | (c5a & c5 ) | (p23 & c5 );        // → bit 7
    assign s6  = s6a ^ s6b;
    assign c6  = s6a & s6b;                                      // → bit 7

    // --- bit 7: FA(p06, p15, p24), FA(c6a, c6b, c6), HA(fa_s_a, fa_s_b) ---
    logic s7a, c7a, s7b, c7b, s7, c7;
    assign s7a = p06 ^ p15 ^ p24;
    assign c7a = (p06 & p15) | (p15 & p24) | (p06 & p24);        // → bit 8
    assign s7b = c6a ^ c6b ^ c6;
    assign c7b = (c6a & c6b) | (c6b & c6 ) | (c6a & c6 );        // → bit 8
    assign s7  = s7a ^ s7b;
    assign c7  = s7a & s7b;                                      // → bit 8

    // --- bit 8: FA(a4, p07, p16), FA(p25, p34, c7a), FA(s8a, s8b, c7b), HA(fa_s, c7) ---
    logic s8a, c8a, s8b, c8b, s8c, c8c, s8, c8;
    assign s8a = a4  ^ p07 ^ p16;
    assign c8a = (a4  & p07) | (p07 & p16) | (a4  & p16);        // → bit 9
    assign s8b = p25 ^ p34 ^ c7a;
    assign c8b = (p25 & p34) | (p34 & c7a) | (p25 & c7a);        // → bit 9
    assign s8c = s8a ^ s8b ^ c7b;
    assign c8c = (s8a & s8b) | (s8b & c7b) | (s8a & c7b);        // → bit 9
    assign s8  = s8c ^ c7;
    assign c8  = s8c & c7;                                       // → bit 9

    // --- bit 9: FA(p17, p26, p35), FA(c8a, c8b, c8c), FA(s9a, s9b, c8) ---
    logic s9a, c9a, s9b, c9b, s9, c9;
    assign s9a = p17 ^ p26 ^ p35;
    assign c9a = (p17 & p26) | (p26 & p35) | (p17 & p35);        // → bit 10
    assign s9b = c8a ^ c8b ^ c8c;
    assign c9b = (c8a & c8b) | (c8b & c8c) | (c8a & c8c);        // → bit 10
    assign s9  = s9a ^ s9b ^ c8;
    assign c9  = (s9a & s9b) | (s9b & c8 ) | (s9a & c8 );        // → bit 10

    // --- bit 10: FA(a5, p27, p36), FA(p45, c9a, c9b), FA(s10a, s10b, c9) ---
    logic s10a, c10a, s10b, c10b, s10, c10;
    assign s10a = a5  ^ p27 ^ p36;
    assign c10a = (a5  & p27) | (p27 & p36) | (a5  & p36);       // → bit 11
    assign s10b = p45 ^ c9a ^ c9b;
    assign c10b = (p45 & c9a) | (c9a & c9b) | (p45 & c9b);       // → bit 11
    assign s10  = s10a ^ s10b ^ c9;
    assign c10  = (s10a & s10b) | (s10b & c9 ) | (s10a & c9 );   // → bit 11

    // --- bit 11: FA(p37, p46, c10a), FA(s11a, c10b, c10) ---
    logic s11a, c11a, s11, c11;
    assign s11a = p37  ^ p46  ^ c10a;
    assign c11a = (p37  & p46 ) | (p46  & c10a) | (p37  & c10a); // → bit 12
    assign s11  = s11a ^ c10b ^ c10;
    assign c11  = (s11a & c10b) | (c10b & c10 ) | (s11a & c10 ); // → bit 12

    // --- bit 12: FA(a6, p47, p56), FA(s12a, c11a, c11) ---
    logic s12a, c12a, s12, c12;
    assign s12a = a6  ^ p47 ^ p56;
    assign c12a = (a6  & p47) | (p47 & p56) | (a6  & p56);       // → bit 13
    assign s12  = s12a ^ c11a ^ c11;
    assign c12  = (s12a & c11a) | (c11a & c11 ) | (s12a & c11 ); // → bit 13

    // --- bit 13: FA(p57, c12a, c12) ---
    logic s13, c13;
    assign s13 = p57  ^ c12a ^ c12;
    assign c13 = (p57  & c12a) | (c12a & c12 ) | (p57  & c12 );  // → bit 14

    // --- bit 14: FA(a7, p67, c13) ---
    logic s14, c14;
    assign s14 = a7  ^ p67 ^ c13;
    assign c14 = (a7  & p67) | (p67 & c13) | (a7  & c13);        // → bit 15

    // -------------------------------------------------------------------------
    // Output assembly (each column is now a single bit — no final CPA needed)
    // -------------------------------------------------------------------------
    assign out_o[0]  = a0;
    assign out_o[1]  = 1'b0;
    assign out_o[2]  = s2;
    assign out_o[3]  = s3;
    assign out_o[4]  = s4;
    assign out_o[5]  = s5;
    assign out_o[6]  = s6;
    assign out_o[7]  = s7;
    assign out_o[8]  = s8;
    assign out_o[9]  = s9;
    assign out_o[10] = s10;
    assign out_o[11] = s11;
    assign out_o[12] = s12;
    assign out_o[13] = s13;
    assign out_o[14] = s14;
    assign out_o[15] = c14;

endmodule
