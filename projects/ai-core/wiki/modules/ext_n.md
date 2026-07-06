# Extender N

`ext_n` — Parameterized extender: widens each of `SIZE` `WIDTH`-bit inputs by `EXT` bits, to `WIDTH + EXT`.

## Purpose

Sign- or zero-extends a group of values to a wider field — the width-matching step before values of differing widths share an adder or compressor. It is reused inside the compressors [cpr_c_n](./cpr_c_n.md) and [cpr_w_n](./cpr_w_n.md) to widen their inputs.

## Parameters

| Parameter   | Default | Description                                   |
| ----------- | ------- | --------------------------------------------- |
| `WIDTH`     | 8       | Bit width of each input word.                 |
| `SIZE`      | 4       | Number of input words.                        |
| `EXT`       | 4       | Number of bits added at the top of each word. |
| `IS_SIGNED` | 1       | `1` = sign-extend, `0` = zero-extend.         |

`OUT_WIDTH` (derived `localparam`) `= WIDTH + EXT` — the extended word width.

## Interface

| Signal  | Dir | Width                | Description                                   |
| ------- | --- | -------------------- | --------------------------------------------- |
| `in_i`  | in  | `SIZE` × `WIDTH`     | Input words — unpacked array `[0:SIZE-1]`.    |
| `out_o` | out | `SIZE` × `OUT_WIDTH` | Extended words — unpacked array `[0:SIZE-1]`. |

## Instantiation

```systemverilog
ext_n #(
    .WIDTH     (8),
    .SIZE      (4),
    .EXT       (4),
    .IS_SIGNED (1'b1)
) ext_n_i (
    .in_i  (in),
    .out_o (out)
);
```

## Internal logic

The module is purely combinational. It applies the same one-liner extension to every word of the input array independently, growing each from `WIDTH` to `OUT_WIDTH = WIDTH + EXT` bits.

### Per-word generate loop

```systemverilog
genvar i;
generate
    for (i = 0; i < SIZE; i++) begin : gen_ext
        assign out_o[i] = {{EXT{(IS_SIGNED ? in_i[i][WIDTH-1] : 1'b0)}}, in_i[i]};
    end
endgenerate
```

The `generate for` loop unrolls at elaboration into `SIZE` identical, parallel assignments — one per array element `i`. There is no interaction between words: each `out_o[i]` depends only on the matching `in_i[i]`, so the block is really `SIZE` copies of a single-word extender laid side by side.

### The extension bits

Each output word is a concatenation of two fields:

- **Low field — the original value:** `in_i[i]` occupies the low `WIDTH` bits unchanged.
- **High field — the added bits:** `{EXT{ ... }}` replicates a single fill bit `EXT` times and prepends it. The fill bit is chosen by the ternary `(IS_SIGNED ? in_i[i][WIDTH-1] : 1'b0)`:
  - When `IS_SIGNED = 1`, the fill is the word's own MSB `in_i[i][WIDTH-1]` — a *sign extension*: replicating the sign bit widens the two's-complement value while preserving its numeric magnitude and sign.
  - When `IS_SIGNED = 0`, the fill is `1'b0` — a *zero extension*: the value is treated as non-negative and the new high bits are simply zeros.

Unlike [add_n](./add_n.md), whose `is_signed_i` is a runtime port, `IS_SIGNED` here is a compile-time parameter: a datapath's position fixes whether its operands are signed, so the choice is baked in per instance (the same rationale [cpr_w_n](./cpr_w_n.md) uses when it instantiates this module with `.IS_SIGNED(IS_SIGNED)`). This makes the fill bit a constant `1'b0` for the whole unsigned instance, letting synthesis drop the sign-bit fanout entirely.

Source: [ext_n.sv](../../rtl/ext_n.sv)
