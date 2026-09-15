# Dot Product 8 Alpha (Square)

`dp_8_alpha_sqr` — the A-only generator DP8 for the square datapath. It is [dp_8_sqr](./dp_8_sqr.md) with the **B operand removed**: same structure and widths, but instead of adding a per-lane `b` before each square it injects the removed B operand's `−8` bias. It produces the per-DP8 **alpha** square-sum in 18-bit carry-save form.

## Purpose

α is the A-only correction term of `Result = ½(PE − α − β + C)`. Per DP8 it is

```
ALPHA_DP8 = 2^4 · Σ_k (AH_k − 8·bu)²  +  Σ_k (AL_k − 8·bu)²        bu = ~is_signed_b
```

over the eight pre-centered A nibbles `{AH, AL}`. The removed B operand's `−8` (when B is unsigned) replaces `dp_8_sqr`'s per-lane add of `b`: two [gate_n_sqr](./gate_n_sqr.md) banks, both driven by `is_signed_b_i`, sign-extend the nibble (B signed) or subtract 8 (B unsigned) into the 5-bit squarer argument. Everything downstream — 16 [s_5_bit_sqr](./s_5_bit_sqr.md), two unsigned [cpr_w_n](./cpr_w_n.md) 8:2, AH block `<<4`, one unsigned `cpr_w_n` 4:2 → 18-bit — is identical to [dp_8_sqr](./dp_8_sqr.md). No α/β/C/½ here; the reconstruction is downstream (`acc_array_sqr`).

Idle DP8s are clean **without a zero port**: `ctrl` forces `is_signed_b = 1` there, so a dispatcher-zeroed A sign-extends to a real `0`.

## Interface

| Signal              | Dir | Width   | Description                                                |
| ------------------- | --- | ------- | ---------------------------------------------------------- |
| `a_i[0:7]`          | in  | 8 each  | Pre-centered int8 A lanes (`{AH, AL}` nibbles).            |
| `is_signed_b_i`     | in  | 1       | Removed-B signedness; `0` (unsigned) → subtract 8.         |
| `sum_o` / `carry_o` | out | 18 each | Carry-save `ALPHA_DP8` (16-bit value + 2 guard, unsigned). |

The `is_signed_a`/`is_signed_b`/`b_i` of `dp_8_sqr` are gone; only `is_signed_b_i` (the removed operand) remains, and A arrives pre-centered.

## Internal logic

```systemverilog
assign ah[k] = a_i[k][NIB_WIDTH +: NIB_WIDTH];
assign al[k] = a_i[k][0         +: NIB_WIDTH];

gate_n_sqr #(.WIDTH(NIB_WIDTH), .SIZE(LANES)) gate_n_sqr_ah_i (
    .in_i(ah), .is_signed_i(is_signed_b_i), .out_o(arg_ah)
);
gate_n_sqr #(.WIDTH(NIB_WIDTH), .SIZE(LANES)) gate_n_sqr_al_i (
    .in_i(al), .is_signed_i(is_signed_b_i), .out_o(arg_al)
);
// 16 s_5_bit_sqr, two cpr_w_n 8:2 (unsigned), AH << 4, cpr_w_n 4:2 -> 18-bit
```

Widths are identical to [dp_8_sqr](./dp_8_sqr.md): the argument range `[−16,7]` squares to `[0,256]` (9-bit), same as the PE's `[−16,14]`, so the 8:2 (12-bit), `<<4` (16-bit) and 4:2 (18-bit) chain is unchanged. Combinational.

Diagram: [dp_8_alpha_sqr](../../doc/diagrams/dp_8_alpha_sqr.excalidraw).

Source: [dp_8_alpha_sqr.sv](../../rtl/dp_8_alpha_sqr.sv) — instantiated by [pe_array_alpha_sqr](./pe_array_alpha_sqr.md)
