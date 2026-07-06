# Shifter N

`shift_n` — Parameterized conditional left shifter: optionally shifts each of `SIZE` `WIDTH`-bit inputs left by `SHIFT`, widening the output to `WIDTH + SHIFT` bits so the shifted value is never truncated.

## Purpose

Applies a programmable power-of-two weight (`2^SHIFT`) to a group of values, or passes them through unchanged, under a single shared select — the per-level weighting step of a reduction tree.

## Parameters

| Parameter   | Default | Description                                                   |
| ----------- | ------- | ------------------------------------------------------------- |
| `WIDTH`     | 8       | Bit width of each input word.                                 |
| `SIZE`      | 4       | Number of input words (all share the select).                 |
| `SHIFT`     | 4       | Left-shift amount applied when selected.                      |
| `IS_SIGNED` | 1       | Pass-through extension: `1` = sign-extend, `0` = zero-extend. |

`OUT_WIDTH` (derived `localparam`) `= WIDTH + SHIFT` — the result word width.

## Interface

| Signal  | Dir | Width                | Description                                      |
| ------- | --- | -------------------- | ------------------------------------------------ |
| `in_i`  | in  | `SIZE` × `WIDTH`     | Input words — unpacked array `[0:SIZE-1]`.       |
| `sel_i` | in  | 1                    | `1` = shift left by `SHIFT`; `0` = pass through. |
| `out_o` | out | `SIZE` × `OUT_WIDTH` | Result words — unpacked array `[0:SIZE-1]`.      |

## Instantiation

```systemverilog
shift_n #(
    .WIDTH     (8),
    .SIZE      (4),
    .SHIFT     (4),
    .IS_SIGNED (1'b1)
) shift_n_i (
    .in_i  (in),
    .sel_i (sel),
    .out_o (out)
);
```

## Internal logic

The module is purely combinational. It applies one conditional expression per input word, all governed by the single shared `sel_i`, and every word grows from `WIDTH` to `OUT_WIDTH = WIDTH + SHIFT` bits so the largest possible result fits without loss.

### Per-word generate loop

```systemverilog
genvar i;
generate
    for (i = 0; i < SIZE; i++) begin : gen_shift
        assign out_o[i] = sel_i
            ? {in_i[i], {SHIFT{1'b0}}}
            : {{SHIFT{(IS_SIGNED ? in_i[i][WIDTH-1] : 1'b0)}}, in_i[i]};
    end
endgenerate
```

The `generate for` loop unrolls at elaboration into `SIZE` identical, parallel assignments — one per array element `i`. The words do not interact: each `out_o[i]` is a function of only `in_i[i]` and the common `sel_i`. Each assignment is a 2-to-1 choice between a shifted form and a pass-through form, both already sized to `OUT_WIDTH`.

### Shift path (`sel_i = 1`)

```systemverilog
{in_i[i], {SHIFT{1'b0}}}
```

The word is placed in the high bits and `SHIFT` zeros are appended in the low bits. Appending `SHIFT` zero LSBs is exactly a left shift by `SHIFT`, i.e. multiplication by `2^SHIFT`. Because the output is `WIDTH + SHIFT` bits wide, the whole shifted value is retained — nothing falls off the top. This path is independent of `IS_SIGNED`: a left shift by zero-fill is identical for signed and unsigned values.

### Pass-through path (`sel_i = 0`)

```systemverilog
{{SHIFT{(IS_SIGNED ? in_i[i][WIDTH-1] : 1'b0)}}, in_i[i]}
```

When not shifting, the word must still be widened to `OUT_WIDTH` so both branches share a width. This is the same extension performed by [ext_n](./ext_n.md), with the extension amount equal to `SHIFT`: `SHIFT` fill bits are prepended, each being the sign bit `in_i[i][WIDTH-1]` when `IS_SIGNED` (sign extension, preserving a two's-complement value) or `1'b0` otherwise (zero extension). The numeric value is unchanged; only the field width grows.

`IS_SIGNED` is a compile-time parameter because a shifter's fixed position in the datapath fixes whether its operands are signed — the same rationale used by [ext_n](./ext_n.md) and [cpr_w_n](./cpr_w_n.md). Note it only affects the pass-through branch; the shift branch always zero-fills.

Source: [shift_n.sv](../../rtl/shift_n.sv)
