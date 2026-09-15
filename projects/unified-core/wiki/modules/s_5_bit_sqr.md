# Signed 5-bit Squarer

`s_5_bit_sqr` — an optimized signed 5-bit squarer: it maps a two's-complement input `in_i ∈ [−16, 15]` to its square `out_o ∈ [0, 256]` as a flat pile of minimized Boolean gates, with no multiplier and no submodules.

## Purpose

The per-lane square used by [dp_8_sqr](./dp_8_sqr.md)'s add-then-square: each lane forms a centered 5-bit signed sum `(nibble + b)` and squares it here. `dp_8_sqr` instantiates **16** of these (8 for the high-nibble block, 8 for the low-nibble block). Because a square is never negative, the output is **unsigned 9-bit**; only the single input `−16` reaches `256` and sets the 9th bit.

Each output bit is a Karnaugh-map-minimized function of the five raw input bits (`s = in_i[4]` sign, `a3..a0 = in_i[3:0]`) derived over the full 32-entry truth table, so the module synthesizes to a small fixed gate cloud rather than a `x*x` multiply. The low five bits (`out_o[4:0]`) are **sign-independent** — the same formulas as an unsigned 4-bit square on the raw bits — and only `out_o[7:5]` and `out_o[8]` depend on the sign.

## Parameters

None — fixed 5-bit-in / 9-bit-out.

## Interface

| Signal  | Dir | Width | Description                                    |
| ------- | --- | ----- | ---------------------------------------------- |
| `in_i`  | in  | 5     | Signed operand, two's complement, `[−16, 15]`. |
| `out_o` | out | 9     | Unsigned square `in_i²`, `[0, 256]`.           |

## Instantiation

```systemverilog
s_5_bit_sqr sqr_i (
    .in_i (add),   // logic signed [4:0]
    .out_o(sq)     // logic [8:0]
);
```

## Internal logic

Purely combinational — nine continuous assignments, each a minimized Boolean function of `{s, a3, a2, a1, a0} = in_i`:

```systemverilog
assign out_o[0] = a0;
assign out_o[1] = 1'b0;
assign out_o[2] = a1 & ~a0;
assign out_o[3] = a0 & (a1 ^ a2);
assign out_o[4] = (a0 & (a2 ^ a3)) | (a2 & ~a1 & ~a0);
assign out_o[5] = (~a0 & a1 & (a3 ^ a2)) |
                  ( a0 & (((a3 & (a2 | a1)) | (a2 & a1)) ^ s));
assign out_o[6] = (~s & a3 & (~a2 | a1)) |
                  ( s & a3 & ~a2 & ~a1 & ~a0) |
                  ( s & ~a3 & ((a1 ^ a0) | (a2 & a1)));
assign out_o[7] = (~s & a3 & a2) | (s & ~a3 & (a2 ^ (a0 | a1)));
assign out_o[8] = s & ~a3 & ~a2 & ~a1 & ~a0;
```

- **`out_o[4:0]` — sign-independent.** The low five bits of `x²` depend only on `|x|`'s low bits; they reduce to the same expressions an unsigned 4-bit squarer would produce on the raw `a3..a0`. `out_o[1]` is always `0` (the weight-2 bit of any square is 0).
- **`out_o[7:5]` — sign-dependent.** These carry the terms that differ between `x` and `−x` above the low bits, minimized directly from the 5-variable truth table.
- **`out_o[8]` — the overflow bit.** Set for exactly one input: `in_i = −16` (`s=1`, `a3..a0=0`), whose square `256` is the only value needing the 9th bit. Every other input squares to at most `15² = 225` (fits 8 bits) or `14² = 196`.

Verified at the corners by [dp_8_sqr](./dp_8_sqr.md)'s testbench (e.g. `−16 → 256`, `15 → 225`, `−1 → 1`).

Source: [s_5_bit_sqr.sv](../../rtl/s_5_bit_sqr.sv) — Used by: [dp_8_sqr](./dp_8_sqr.md)
