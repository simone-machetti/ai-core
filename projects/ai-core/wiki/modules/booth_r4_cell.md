# Booth Radix-4 Cell

`booth_r4_cell` — a single radix-4 Booth selector: turns one 3-bit window of the recoded multiplier into one partial product of the multiplicand.

## Purpose

Maps a 3-bit Booth selector onto one of the five radix-4 multiples `{0, +1×, +2×, -1×, -2×}` of the multiplicand `mult_i`, producing one partial product. The output is two bits wider than the input to hold the doubled (`2×`) and negated cases. It is instantiated `PP_SIZE` times by [booth_r4](./booth_r4.md), once per selector window.

## Parameters

| Parameter  | Default | Description                             |
| ---------- | ------- | --------------------------------------- |
| `IN_WIDTH` | 16      | Bit width of the multiplicand `mult_i`. |

`OUT_WIDTH` (derived) `= IN_WIDTH + 2` — two extra MSBs so `2×` (a left shift) and the two's-complement negation never overflow.

## Interface

| Signal        | Dir | Width       | Description                                                                   |
| ------------- | --- | ----------- | ----------------------------------------------------------------------------- |
| `mult_i`      | in  | `IN_WIDTH`  | Multiplicand (the wider operand in [booth_r4](./booth_r4.md)).                |
| `sel_i`       | in  | 3           | Radix-4 Booth selector — a 3-bit overlapping window of the multiplier.        |
| `is_signed_i` | in  | 1           | Multiplicand extension: `1` = sign-extend, `0` = zero-extend. Runtime signal. |
| `pp_o`        | out | `OUT_WIDTH` | Partial product for this selector.                                            |

`is_signed_i` is a **runtime** input, not a parameter: signedness follows the datapath operating mode ([dp_8](./dp_8.md)) and can change cycle to cycle.

## Instantiation

```systemverilog
booth_r4_cell #(
    .IN_WIDTH(8)
) booth_r4_cell_i (
    .mult_i     (a),
    .sel_i      (sel),
    .is_signed_i(is_signed),
    .pp_o       (pp)
);
```

## Internal logic

Purely combinational — no clock, no storage. Two steps: extend the multiplicand, then decode the selector.

### Multiplicand extension

Before any multiple is formed, the multiplicand is widened by two bits at the top:

```systemverilog
logic [OUT_WIDTH-1:0] m_ext;
assign m_ext = {{2{is_signed_i ? mult_i[IN_WIDTH-1] : 1'b0}}, mult_i};
```

- When `is_signed_i = 1`, the two new MSBs replicate `mult_i[IN_WIDTH-1]` (sign-extension), so `m_ext` is the two's-complement value of `mult_i` in `OUT_WIDTH` bits.
- When `is_signed_i = 0`, the two new MSBs are `0` (zero-extension), so `m_ext` is the unsigned value.

Two extra bits (not one) are needed because the `2×` multiple shifts `m_ext` left by one, and the negated multiples take a two's complement — both require headroom above the original MSB.

### Selector decode and the radix-4 recode table

A `case` on `sel_i` picks the multiple:

```systemverilog
always_comb begin
    case (sel_i)
        3'b001:  pp_o = m_ext;          // +1x
        3'b010:  pp_o = m_ext;          // +1x
        3'b011:  pp_o = m_ext <<< 1;    // +2x
        3'b100:  pp_o = -(m_ext <<< 1); // -2x
        3'b101:  pp_o = -m_ext;         // -1x
        3'b110:  pp_o = -m_ext;         // -1x
        default: pp_o = '0;             // 000, 111 -> 0
    endcase
end
```

The 3-bit window is `sel_i = {b[2i+1], b[2i], b[2i-1]}` (see [booth_r4](./booth_r4.md) for how the window is sliced). The radix-4 Booth digit it encodes is

```
d = -2·sel_i[2] + sel_i[1] + sel_i[0]
```

which yields exactly the table below — matching the `case` line for line:

| `sel_i` | `b[2i+1]` | `b[2i]` | `b[2i-1]` | digit `d` | Operation | `pp_o`           |
| ------- | --------- | ------- | --------- | --------- | --------- | ---------------- |
| `000`   | 0         | 0       | 0         | `0`       | 0         | `'0`             |
| `001`   | 0         | 0       | 1         | `+1`      | `+1×`     | `m_ext`          |
| `010`   | 0         | 1       | 0         | `+1`      | `+1×`     | `m_ext`          |
| `011`   | 0         | 1       | 1         | `+2`      | `+2×`     | `m_ext <<< 1`    |
| `100`   | 1         | 0       | 0         | `-2`      | `-2×`     | `-(m_ext <<< 1)` |
| `101`   | 1         | 0       | 1         | `-1`      | `-1×`     | `-m_ext`         |
| `110`   | 1         | 1       | 0         | `-1`      | `-1×`     | `-m_ext`         |
| `111`   | 1         | 1       | 1         | `0`       | 0         | `'0`             |

`+2×` is a hard left shift (`<<< 1`); `-1×` and `-2×` are `OUT_WIDTH`-bit two's-complement negations of `m_ext` and `m_ext <<< 1`. Because the negations are taken in the extended width, the sign of each negative partial product is carried in the two spare MSBs — the consumer ([dp_8](./dp_8.md)) sign-extends and weights each `pp_o` when it sums them.

Source: [booth_r4_cell.sv](../../rtl/booth_r4_cell.sv)
