---
type: module
title: Adder N
description: Parameterized two-input adder with a WIDTH+1 result so the sum never overflows.
resource: rtl/add_n.sv
---

# Adder N

`add_n` — Parameterized two-input adder producing a `WIDTH + 1`-bit result so the sum never overflows.

## Purpose

Adds two `WIDTH`-bit operands into a `WIDTH + 1`-bit result, the extra bit holding the carry or overflow. A runtime `is_signed_i` select chooses signed (two's-complement) or unsigned addition, so the same instance can switch mode — e.g. the low word of a fused accumulator resolving unsigned while the high or standalone word resolves signed.

## Parameters

| Parameter | Default | Description                |
| --------- | ------- | -------------------------- |
| `WIDTH`   | 8       | Bit width of each operand. |

`OUT_WIDTH` (derived `localparam`) `= WIDTH + 1` — the result width.

## Interface

| Signal        | Dir | Width       | Description                                                       |
| ------------- | --- | ----------- | ----------------------------------------------------------------- |
| `in_0_i`      | in  | `WIDTH`     | First operand.                                                    |
| `in_1_i`      | in  | `WIDTH`     | Second operand.                                                   |
| `is_signed_i` | in  | 1           | `1` = signed (sign-extended) add; `0` = unsigned (zero-extended). |
| `out_o`       | out | `OUT_WIDTH` | Sum `in_0_i + in_1_i`, with no overflow.                          |

## Instantiation

```systemverilog
add_n #(
    .WIDTH (8)
) add_n_i (
    .in_0_i      (a),
    .in_1_i      (b),
    .is_signed_i (is_signed),
    .out_o       (sum)
);
```

## Internal logic

The module is purely combinational. It widens both operands from `WIDTH` to `OUT_WIDTH = WIDTH + 1` bits, then adds the two widened values with a single `+`. The one extra bit is what guarantees no overflow: two `WIDTH`-bit numbers can produce a result that needs one more bit, and here that bit is always present.

### Extending the operands by one bit

```systemverilog
logic [OUT_WIDTH-1:0] ext_0;
logic [OUT_WIDTH-1:0] ext_1;

assign ext_0 = {(is_signed_i ? in_0_i[WIDTH-1] : 1'b0), in_0_i};
assign ext_1 = {(is_signed_i ? in_1_i[WIDTH-1] : 1'b0), in_1_i};
```

Each operand is placed in the low `WIDTH` bits of a `WIDTH + 1`-bit word, and one new top bit is prepended by concatenation. The value of that top bit is chosen at *runtime* by `is_signed_i`:

- **Signed (`is_signed_i = 1`):** the new bit is a copy of the operand's own MSB `in_x_i[WIDTH-1]` — a one-bit *sign extension*. In two's complement, replicating the sign bit preserves the numeric value while widening the field, so a negative operand stays negative.
- **Unsigned (`is_signed_i = 0`):** the new bit is `1'b0` — a *zero extension*. The value is treated as non-negative and simply gains a leading zero.

Because `is_signed_i` is a port (not a parameter), a single hardware instance carries both a sign-extend and a zero-extend path and picks between them per cycle. Contrast this with [ext_n](./ext_n.md) and [shift_n](./shift_n.md), whose signedness is fixed at compile time by a parameter.

### The add and the overflow bit

```systemverilog
assign out_o = ext_0 + ext_1;
```

The two extended words are added at the full `OUT_WIDTH`. One extra bit is always sufficient:

- **Unsigned:** the largest sum is `(2^WIDTH − 1) + (2^WIDTH − 1) = 2^(WIDTH+1) − 2`, which fits in `WIDTH + 1` bits, so the top bit captures the carry-out and the result never wraps.
- **Signed:** sign-extending each operand by one bit doubles the representable range, which is exactly enough to hold the sum of two `WIDTH`-bit signed numbers without overflow; `out_o[WIDTH]` is the correct sign of the result.

The low `WIDTH` bits of `out_o` are identical in both modes — the mode only affects the most-significant (overflow/sign) bit, since that is the only bit the extension changed.

Source: [add_n.sv](../../rtl/add_n.sv)
