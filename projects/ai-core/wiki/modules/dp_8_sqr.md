# Dot Product 8 (Square)

`dp_8_sqr` is the **add-then-square** replacement for [dp_8](./dp_8.md) in the square PE variant: it computes the same 8-lane `int8 × int4` DP8 shape, but each `4×4` multiply becomes a centered add-and-square, and it returns the raw **square-sum** `S_DP8` in carry-save form. See the diagram companion at [dp_8_sqr](../../doc/diagrams/dp_8_sqr.excalidraw).

## Purpose

`dp_8_sqr` is the first bottom-up module (Gate 1) of the square variant, a drop-in for [dp_8](./dp_8.md) that trades the Booth multiplier for squarers. It does **not** compute the dot product itself — it emits only the square-sum

```
S_DP8 = 2^4 · Σ_{k=0..7} (AH_k + b_k)²  +  Σ_{k=0..7} (AL_k + b_k)²
```

where each `int8` operand `a` is split into two nibbles `{AH, AL}` and `b` is the `int4` nibble. The true dot product is recovered downstream as `Σ a_k·b_k = ½·(S_DP8 − α − β + C)` — the A-only term `α`, the B-only term `β` (amortized per grid row / column) and the per-mode constant `C` live outside this core; `dp_8_sqr` carries none of them.

Two things distinguish it from `dp_8`:

- **Pre-centered inputs.** The dispatcher has already biased every originally-unsigned nibble by `−8` (flipping its MSB), so every nibble arriving here is signed in `[−8, 7]`. `dp_8_sqr` therefore needs **no `is_signed` ports** — the per-slice signedness is fully absorbed into the centering. Adding two centered nibbles gives a 5-bit signed value in `[−16, 14]`.
- **Unsigned, non-negative output.** `S_DP8` is a sum of squares, so the carry-save pair is **unsigned** and carries **no sign-consistency contract** — the hardest property of `dp_8` (a sign-extendable carry-save pair) simply vanishes. All three compressors run `IS_SIGNED = 0`.

## Parameters

Like `dp_8`, `dp_8_sqr` is **deliberately specialized** — every value is a `localparam`, no overridable parameters. The leaf primitives it builds on ([s_5_bit_sqr](./s_5_bit_sqr.md), [cpr_w_n](./cpr_w_n.md)) stay general.

| Parameter    | Default (fixed)                   | Description                                                 |
| ------------ | --------------------------------- | ----------------------------------------------------------- |
| `LANES`      | `8`                               | Dot-product lanes.                                          |
| `IN_WIDTH_A` | `8`                               | `a_i` width — two centered signed nibbles `{AH, AL}`.       |
| `IN_WIDTH_B` | `4`                               | `b_i` width — one centered signed nibble.                   |
| `NIB_WIDTH`  | `4`                               | Nibble width.                                               |
| `SUM_WIDTH`  | `5`                               | Centered nibble-pair sum `(AH/AL + b)`, signed `[−16, 14]`. |
| `SQ_WIDTH`   | `9`                               | Square output — unsigned `[0, 256]`.                        |
| `CPR8_WIDTH` | `SQ_WIDTH + $clog2(LANES)` = `12` | Per-block 8:2 compressor output (unsigned sum-of-8 ≤ 2048). |
| `NUM_BLK`    | `2`                               | The AH and AL blocks.                                       |
| `SHIFT_AH`   | `4`                               | `2^4` positional weight of the high-nibble block.           |
| `FINAL_IN`   | `CPR8_WIDTH + SHIFT_AH` = `16`    | Final compressor input width, set by the `<< 4` AH row.     |
| `FINAL_EXT`  | `2`                               | Guard bits on the final compressor.                         |
| `OUT_WIDTH`  | `FINAL_IN + FINAL_EXT` = `18`     | Carry-save output width (16-bit `S_DP8` + 2 guard bits).    |

## Interface

| Signal     | Dir | Width  | Description                                                 |
| ---------- | --- | ------ | ----------------------------------------------------------- |
| `a_i[0:7]` | in  | 8 each | Pre-centered A — two signed nibbles `{AH, AL}` per lane.    |
| `b_i[0:7]` | in  | 4 each | Pre-centered B — one signed nibble per lane.                |
| `sum_o`    | out | 18     | Carry-save sum row.                                         |
| `carry_o`  | out | 18     | Carry-save carry row; `sum_o + carry_o = S_DP8` (unsigned). |

## Instantiation

No overridable parameters — only ports are connected:

```systemverilog
dp_8_sqr dp_8_sqr_i (
    .a_i    (a),      // logic [7:0] a [0:7], pre-centered {AH, AL}
    .b_i    (b),      // logic [3:0] b [0:7], pre-centered nibble
    .sum_o  (sum),    // logic [17:0]
    .carry_o(carry)   // logic [17:0]
);
```

## Internal logic

`dp_8_sqr` is fully **combinational** and stays in **carry-save** form from the first compression to the output. The datapath:

```
16× (center-add + s_5_bit_sqr)  →  2 per-block 8:2 cpr_w_n  →  AH << 4  →  1 final 4:2 cpr_w_n (EXT=2)
 (AH+b, AL+b squared, 9b each)     (AH block, AL block, 12b)  (weight 2^4)  (4 rows → 2 rows, 18b: sum_o, carry_o)
```

### Nibble split & centered add

Per lane, the two signed nibbles of `a_i` and the single `b_i` nibble are sign-extended and added into two 5-bit signed sums (`[−16, 14]`):

```systemverilog
assign ah = a_i[k][NIB_WIDTH +: NIB_WIDTH];  // signed high nibble
assign al = a_i[k][0         +: NIB_WIDTH];  // signed low  nibble
assign b  = b_i[k];

assign add_ah = ah + b;   // 5-bit signed
assign add_al = al + b;
```

`ah`/`al`/`b` are declared `signed`, so the width-5 destination sign-extends each 4-bit nibble before adding — no `−8` bias is applied here, because the operands arrived already centered.

### Per-lane squares (16× s_5_bit_sqr)

Each 5-bit signed sum is squared to a 9-bit unsigned value by an [s_5_bit_sqr](./s_5_bit_sqr.md); there are two per lane (AH block, AL block), 16 in all:

```systemverilog
s_5_bit_sqr sqr_ah_i (.in_i(add_ah), .out_o(sq_ah[k]));
s_5_bit_sqr sqr_al_i (.in_i(add_al), .out_o(sq_al[k]));
```

### Per-block compression (two unsigned 8:2)

The eight AH squares and the eight AL squares are each reduced by an 8:2 [cpr_w_n](./cpr_w_n.md), unsigned:

```systemverilog
cpr_w_n #(
    .IN_WIDTH (SQ_WIDTH),      // 9
    .IN_SIZE  (LANES),         // 8 → 8:2
    .EXT      ($clog2(LANES)), // 3 growth bits
    .IS_SIGNED(1'b0)           // unsigned (squares are non-negative)
) cpr_w_n_ah_i (
    .in_i   (sq_ah),
    .sum_o  (ah_sum),
    .carry_o(ah_carry)
);
```

Output width is `IN_WIDTH + EXT = 9 + 3 = 12 = CPR8_WIDTH`: `EXT = $clog2(8) = 3` exactly holds the sum of eight `≤256` values (`8 · 256 = 2048 < 2^12`). This is one bit narrower than `dp_8`'s per-weight 8:2 (which adds a `+1` guard for signed sign-consistency) — unnecessary here since the rows are non-negative.

### Weight align & final compression (unsigned 4:2)

The AH block carries weight `2^4`, so its two rows are widened to `FINAL_IN = 16` and shifted `<< 4`; the AL rows pass at weight `2^0`. The four rows are reduced by one 4:2 `cpr_w_n`:

```systemverilog
assign final_in[0] = FINAL_IN'(ah_sum)   << SHIFT_AH;
assign final_in[1] = FINAL_IN'(ah_carry) << SHIFT_AH;
assign final_in[2] = FINAL_IN'(al_sum);
assign final_in[3] = FINAL_IN'(al_carry);

cpr_w_n #(
    .IN_WIDTH (FINAL_IN),    // 16
    .IN_SIZE  (NUM_BLK*2),   // 4 → 4:2
    .EXT      (FINAL_EXT),   // 2 guard bits
    .IS_SIGNED(1'b0)
) cpr_w_n_final_i (
    .in_i   (final_in),
    .sum_o  (sum_o),
    .carry_o(carry_o)
);
```

A 12-bit block row shifted `<< 4` occupies bits `[15:4]`, so `FINAL_IN = 12 + 4 = 16`. `EXT = $clog2(4) = 2` gives the guard for four unsigned rows, and `OUT_WIDTH = 18`.

### The 18-bit output

The two 18-bit rows are the output directly. `S_DP8` peaks at `16·(8·256) + (8·256) = 34816` — a 16-bit value — when every square argument is `−16`; the two guard bits keep the carry-save reduction exact. Unlike `dp_8`, there is **no sign-consistency invariant**: `sum_o + carry_o` resolves to `S_DP8` (mod `2^18`, exact since `S_DP8 < 2^18`) and that is all downstream needs, because the value is non-negative.

### Value range

| Stage                        | Width | Composition                               |
| ---------------------------- | ----- | ----------------------------------------- |
| Centered nibble add          | 5     | signed `(AH/AL + b)` in `[−16, 14]`.      |
| `s_5_bit_sqr` output         | 9     | unsigned square in `[0, 256]`.            |
| Per-block 8:2 cpr (×2)       | 12    | `9 + clog2(8)`, unsigned sum-of-8 ≤ 2048. |
| Weight-`2^4` aligned (`<<4`) | 16    | 12-bit block row shifted `<< 4`.          |
| Final 4:2 cpr (EXT=2)        | 18    | four unsigned rows → two rows.            |
| Output                       | 18    | 16-bit `S_DP8` (≤ 34816) + 2 guard bits.  |

Source: [dp_8_sqr.sv](../../rtl/dp_8_sqr.sv) — Testbench: [tb_dp_8_sqr.sv](../../tb/tb_dp_8_sqr.sv) — Diagram: [dp_8_sqr](../../doc/diagrams/dp_8_sqr.excalidraw)
