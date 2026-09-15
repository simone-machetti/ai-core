# NR4SD Radix-4 Cell

`nr4sd_r4_cell` — a single NR4SD⁺ partial-product cell: turns one 2-bit digit code of the recoded multiplier into one partial product of the multiplicand. The sibling of [booth_r4_cell](./booth_r4_cell.md), with one multiple fewer.

## Purpose

Maps a 2-bit NR4SD⁺ code onto one of the four multiples `{0, +1×, +2×, −1×}` of the multiplicand `mult_i`, producing one partial product. The output is two bits wider than the input to hold the doubled (`2×`) and negated cases. It is instantiated once per lane by [dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md), for the weight-1 digit; the weight-4 digit of the same lane goes to a `booth_r4_cell`.

`−2×` is **absent**: the NR4SD⁺ digit set is `{−1, 0, +1, +2}`, so the shift and the negation are mutually exclusive and the cell never has to build a shifted-and-inverted multiple — one branch fewer than `booth_r4_cell`, whose `{−2 … +2}` needs both `−A` and `−2A`.

## Parameters

| Parameter  | Default | Description                             |
| ---------- | ------- | --------------------------------------- |
| `IN_WIDTH` | 8       | Bit width of the multiplicand `mult_i`. |

`OUT_WIDTH` (derived) `= IN_WIDTH + 2` — two extra MSBs so `2×` (a left shift) and the two's-complement negation never overflow. `CODE_WIDTH = 2` is the NR4SD⁺ code width of [nr4sd_r4](./nr4sd_r4.md).

## Interface

| Signal        | Dir | Width       | Description                                                                   |
| ------------- | --- | ----------- | ----------------------------------------------------------------------------- |
| `mult_i`      | in  | `IN_WIDTH`  | Multiplicand (the A element in [dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md)).        |
| `code_i`      | in  | 2           | NR4SD⁺ digit code, from [nr4sd_r4](./nr4sd_r4.md).                            |
| `is_signed_i` | in  | 1           | Multiplicand extension: `1` = sign-extend, `0` = zero-extend. Runtime signal. |
| `pp_o`        | out | `OUT_WIDTH` | Partial product for this code.                                                |

`is_signed_i` is a **runtime** input, not a parameter: A's signedness follows the operating mode ([dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md)) and can change cycle to cycle. It is the only signedness signal that still reaches the DP8 — B's is consumed in the dispatcher.

## Instantiation

```systemverilog
nr4sd_r4_cell #(
    .IN_WIDTH(8)
) nr4sd_r4_cell_i (
    .mult_i     (a),
    .code_i     (code),
    .is_signed_i(is_signed),
    .pp_o       (pp)
);
```

## Internal logic

Purely combinational — no clock, no storage. Two steps: extend the multiplicand, then decode the code.

### Multiplicand extension

Identical to `booth_r4_cell`: the multiplicand is widened by two bits at the top before any multiple is formed:

```systemverilog
logic [OUT_WIDTH-1:0] m_ext;
assign m_ext = {{2{is_signed_i ? mult_i[IN_WIDTH-1] : 1'b0}}, mult_i};
```

- When `is_signed_i = 1`, the two new MSBs replicate `mult_i[IN_WIDTH-1]` (sign-extension), so `m_ext` is the two's-complement value of `mult_i` in `OUT_WIDTH` bits.
- When `is_signed_i = 0`, the two new MSBs are `0` (zero-extension), so `m_ext` is the unsigned value.

Two extra bits are still needed: `+2×` shifts `m_ext` left by one and `−1×` takes a two's complement, and both want headroom above the original MSB — an unsigned `255` gives `2× = 510` and `−1× = −255`, a 10-bit signed field.

### Code decode and the NR4SD⁺ table

A `case` on `code_i` picks the multiple:

```systemverilog
always_comb begin
    case (code_i)
        2'b01:   pp_o = m_ext;
        2'b10:   pp_o = m_ext <<< 1;
        2'b11:   pp_o = -m_ext;
        default: pp_o = '0;
    endcase
end
```

The code is the one [nr4sd_r4](./nr4sd_r4.md) emits for its low pair, `code = {b_hi ^ (b_lo & c), b_lo ^ c}`, and the digit it encodes gives the table — matching the `case` line for line:

| `code_i` | digit `d` | Operation | `pp_o`        |
| -------- | --------- | --------- | ------------- |
| `00`     | `0`       | 0         | `'0`          |
| `01`     | `+1`      | `+1×`     | `m_ext`       |
| `10`     | `+2`      | `+2×`     | `m_ext <<< 1` |
| `11`     | `−1`      | `−1×`     | `-m_ext`      |

`+2×` is a hard left shift (`<<< 1`); `−1×` is an `OUT_WIDTH`-bit two's-complement negation of `m_ext`. Because the negation is taken in the extended width, the sign of the negative partial product is carried in the two spare MSBs — the consumer sign-extends and weights each `pp_o` when it sums them.

### Why a `case`, not a mux over four multiples

The cell is written as a `case` on the code rather than as a [mux_n](./mux_n.md) over four pre-materialized multiples: the specialized shift/negate structure synthesizes materially smaller than a generic 4:1 mux over four 10-bit words. Measured on the three-digit NR4SD DP8 build, the generic mux gave **211.13** µm² against **191.28** with this cell — the mux alone gave away the whole benefit of hoisting the recoder and more (`dp_8` itself is 202.41).

## Verification

There is no standalone bench: the cell is covered by [tb_dp_8_nr4sd_bfp](../testbenches/tb_dp_8_nr4sd_bfp.md), whose code-space experiment drives every 2-bit code against corner-biased multiplicands under both `is_signed_i` states, and on the code side by the exhaustive [tb_nr4sd_r4](../testbenches/tb_nr4sd_r4.md).

Source: [nr4sd_r4_cell.sv](../../rtl/nr4sd_r4_cell.sv) — Derivation: [nr4sd_plus.tex](../../doc/formulas/encodings/nr4sd_plus.tex)
