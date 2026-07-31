# Subtractor N (BFP)

`sub_n_bfp` — Parameterized unsigned difference unit for BFP alignment: it compares two `WIDTH`-bit unsigned operands and emits the **sign** and the **magnitude** of their difference (`sign_o = (in_1_i > in_0_i)`, `abs_o = |in_0_i − in_1_i|`). It is the exponent-comparison half of [align_cell_bfp](./align_cell_bfp.md), the companion of the shifter [shift_n_bfp](./shift_n_bfp.md).

## Purpose

BFP alignment brings two bundles to their common scale `max(exp_0, exp_1)` by right-shifting the smaller-exponent bundle by `|exp_0 − exp_1|` (see [BFP_imp.md](../../doc/BFP_imp.md) §8, the alignment-block contract). That step needs exactly two facts about the two exponents — *which* one is larger, and *by how much* — and `sub_n_bfp` produces both from a single subtraction:

- **`sign_o`** decides every select inside the cell — which bundle is the max (so which exponent leaves), which bundle is right-shifted, and how the outputs un-swap back to input order.
- **`abs_o`** is the shift amount handed to [shift_n_bfp](./shift_n_bfp.md).

Splitting one comparison into (sign, magnitude) is what lets the cell reuse one shifter and a handful of `mux_n`s instead of a bidirectional shifter: the sign steers the data through a fixed small-to-large shift, the magnitude sizes it.

## Parameters

| Parameter | Default | Description                |
| --------- | ------- | -------------------------- |
| `WIDTH`   | 8       | Operand width (unsigned).  |

`DIFF_WIDTH` (derived `localparam`) `= WIDTH + 1` — the width of the internal signed subtraction. Two `WIDTH`-bit unsigned values differ by at most `±(2^WIDTH − 1)`, which needs one extra bit to hold signed without overflow; the **magnitude** is always below `2^WIDTH`, so `abs_o` stays `WIDTH` wide.

## Interface

| Signal   | Dir | Width   | Description                                                    |
| -------- | --- | ------- | -------------------------------------------------------------- |
| `in_0_i` | in  | `WIDTH` | First unsigned operand (e.g. `exp_0`).                        |
| `in_1_i` | in  | `WIDTH` | Second unsigned operand (e.g. `exp_1`).                       |
| `abs_o`  | out | `WIDTH` | Magnitude `\|in_0_i − in_1_i\|` (the alignment shift amount). |
| `sign_o` | out | 1       | `1` when `in_1_i > in_0_i` (the difference is negative).      |

## Instantiation

```systemverilog
sub_n_bfp #(
    .WIDTH (EXP_WIDTH)
) sub_n_bfp_i (
    .in_0_i (exp_0_i),
    .in_1_i (exp_1_i),
    .abs_o  (amount),
    .sign_o (msb)
);
```

## Internal logic

The module is purely combinational — one wide subtraction, a sign pick-off, and a conditional negate:

```systemverilog
assign diff   = signed'({1'b0, in_0_i}) - signed'({1'b0, in_1_i});
assign sign_o = diff[DIFF_WIDTH-1];
assign abs_o  = sign_o ? WIDTH'(unsigned'(-diff)) : WIDTH'(unsigned'(diff));
```

Both operands are zero-extended by one bit and subtracted as signed `DIFF_WIDTH`-bit values, so `diff` is the true signed difference with no overflow. Its top bit `diff[DIFF_WIDTH-1]` is therefore the sign of `in_0_i − in_1_i`: it is set exactly when `in_1_i > in_0_i`, which is `sign_o`. `abs_o` is the magnitude — `diff` truncated to `WIDTH` bits when non-negative, or `−diff` (also `WIDTH` bits, since the magnitude never reaches `2^WIDTH`) when negative. The `unsigned'` casts keep the truncation from re-extending the sign.

## Notes

- The operands are **unsigned** by contract: BFP exponents are carried bias-agnostic and unsigned (see [BFP_imp.md](../../doc/BFP_imp.md) §10), so an idle/zeroed bundle presented at exponent `0` is the smallest possible value and can never win a `max`. A signed encoding would break that idle-min convention.
- Consumers: [align_cell_bfp](./align_cell_bfp.md) (the alignment cell) drives its whole select network from `sign_o` and feeds `abs_o` straight into [shift_n_bfp](./shift_n_bfp.md).

Source: [sub_n_bfp.sv](../../rtl/sub_n_bfp.sv)
