---
type: module
title: Dot Product 8
description: DP8 (8×4) dot-product core with per-operand signedness — eight int8×int4 MACs in carry-save.
resource: rtl/dp_8.sv
---

# Dot Product 8

`dp_8` is the core MAC primitive: it multiply-accumulates eight `int8 × int4` products into a single carry-save dot product, with each operand's signedness chosen at runtime. See the diagram companion at [doc/diagrams/dp_8.md](../../doc/diagrams/dp_8.md).

## Purpose

`dp_8` computes the length-8 dot product `Σ_{k=0..7} a_k · b_k` of eight `int8 × int4` products and returns it in **carry-save form** — two rows `sum_o`, `carry_o` whose arithmetic sum is the dot product — leaving the final carry-propagate resolve to the downstream reduction tree in [pe_array](../architecture/pe_array.md). It is the most heavily replicated primitive in the design (`pe_array` instantiates 16 of them), so it is hand-sized to the minimum width for its fixed shape while the leaf primitives it builds on stay general. Both operands are independently signed or unsigned (`is_signed_a_i` / `is_signed_b_i`) because the operating modes split each field into a signed high half and an unsigned low half, so all four sign combinations occur across the array.

## Parameters

`dp_8` is **deliberately specialized**: it exposes *no* overridable parameters. Every value below is a `localparam`, fixed to the PE configuration of 8 lanes of `int8 × int4`. This is intentional — the module is the tuned, width-minimized top of the multiplier, whereas its leaf primitives ([booth_r4](./booth_r4.md), [cpr_w_n](./cpr_w_n.md)) remain fully general and parameterized for reuse elsewhere.

| Parameter    | Default (fixed)                       | Description                                                               |
| ------------ | ------------------------------------- | ------------------------------------------------------------------------- |
| `LANES`      | `8`                                   | Number of dot-product lanes (products accumulated).                       |
| `IN_WIDTH_A` | `8`                                   | Multiplicand width — `a_i` is `int8`.                                     |
| `IN_WIDTH_B` | `4`                                   | Multiplier width — `b_i` is `int4` (the Booth-recoded, narrower operand). |
| `PP_SIZE`    | `IN_WIDTH_B/2 + 1` = `3`              | Radix-4 Booth partial products per lane (weights `2^0`, `2^2`, `2^4`).    |
| `PP_WIDTH`   | `IN_WIDTH_A + 2` = `10`               | Width of each Booth partial product (holds `±2·a`).                       |
| `CPR2_WIDTH` | `PP_WIDTH + $clog2(LANES) + 1` = `14` | Output width of each per-weight 8:2 compressor (13-bit sum-of-8 + guard). |
| `FINAL_IN`   | `CPR2_WIDTH + 2·(PP_SIZE-1)` = `18`   | Input width of the final compressor, set by the `<< 4` weight-`2^4` row.  |
| `OUT_WIDTH`  | `FINAL_IN - 1` = `17`                 | Carry-save output width (16-bit dot-product value + 1 guard bit).         |

## Interface

| Signal          | Dir | Width  | Description                                                        |
| --------------- | --- | ------ | ------------------------------------------------------------------ |
| `a_i[0:7]`      | in  | 8 each | Multiplicand elements (`int8`), one per lane.                      |
| `b_i[0:7]`      | in  | 4 each | Multiplier elements (`int4`), one per lane, radix-4 Booth-recoded. |
| `is_signed_a_i` | in  | 1      | Multiplicand (`a`) signedness: `1` = signed, `0` = unsigned.       |
| `is_signed_b_i` | in  | 1      | Multiplier (`b`) signedness: `1` = signed, `0` = unsigned.         |
| `sum_o`         | out | 17     | Carry-save sum row.                                                |
| `carry_o`       | out | 17     | Carry-save carry row; `sum_o + carry_o` = `Σ a_k·b_k`.             |

## Instantiation

`dp_8` has no overridable parameters (all are `localparam`), so only ports are connected:

```systemverilog
dp_8 dp_8_i (
    .a_i          (a),            // logic [7:0] a [0:7]
    .b_i          (b),            // logic [3:0] b [0:7]
    .is_signed_a_i(is_signed_a),
    .is_signed_b_i(is_signed_b),
    .sum_o        (sum),          // logic [16:0]
    .carry_o      (carry)         // logic [16:0]
);
```

## Internal logic

`dp_8` is fully **combinational** and stays in **carry-save** (redundant, two-row) form from the first reduction to the output — there is no carry-propagate adder inside. The datapath is:

```
8× booth_r4  →  3 per-weight 8:2 cpr_w_n  →  sign-extend + shift-align  →  1 final 6:2 cpr_w_n  →  truncate 18→17
 (24 PPs)        (weights 2^0, 2^2, 2^4)      (place each pair at 2^(2j))     (6 rows → 2 rows)      (sum_o, carry_o)
```

The internal storage declares exactly these arrays:

```systemverilog
logic [  PP_WIDTH-1:0] pp        [0:LANES-1][0:PP_SIZE-1];  // 8 lanes × 3 PPs, 10b each
logic [CPR2_WIDTH-1:0] col_sum   [0:PP_SIZE-1];             // per-weight sum row,  14b
logic [CPR2_WIDTH-1:0] col_carry [0:PP_SIZE-1];             // per-weight carry row, 14b
logic [  FINAL_IN-1:0] final_in  [0:2*PP_SIZE-1];           // 6 aligned rows, 18b each
```

### Partial-product generation (8× booth_r4)

One [booth_r4](./booth_r4.md) radix-4 Booth generator is instantiated per lane, all sharing the two signedness controls:

```systemverilog
for (inst = 0; inst < LANES; inst++) begin : gen_booth
    booth_r4 #(
        .IN_WIDTH_A(IN_WIDTH_A),
        .IN_WIDTH_B(IN_WIDTH_B)
    ) booth_r4_i (
        .a_i          (a_i[inst]),
        .b_i          (b_i[inst]),
        .is_signed_a_i(is_signed_a_i),
        .is_signed_b_i(is_signed_b_i),
        .pp_o         (pp[inst])
    );
end
```

Each generator recodes its 4-bit multiplier `b_i[inst]` into radix-4 Booth digits and emits `PP_SIZE = 3` partial products, `pp[inst][0..2]`, each `PP_WIDTH = 10` bits. The three partial products carry the successive radix-4 weights **`2^0`, `2^2`, `2^4`** (weight `2^(2j)` for index `j`), and each is a Booth term drawn from `{0, ±a, ±2a}` on the multiplicand. The `±2a` case is why the width is `IN_WIDTH_A + 2 = 10`: an unsigned `a = 255` gives `2a = 510`, which negated is `−510`, needing a 10-bit signed field. Across all 8 lanes this stage produces `8 × 3 = 24` partial products.

The `2^4` (top) partial product is the extra term that an **unsigned** `b` requires: `booth_r4` sign- or zero-extends `b` above its MSB before recoding, so for a *signed* `b` the top Booth digit recodes to `0` and `pp[*][2]` vanishes, while for an *unsigned* `b` it emits a `{0, +a}` term that supplies the missing positive weight of `b`'s top bit. `PP_SIZE = 3` is therefore the count needed for the unsigned case, and dp_8 always compresses three weights regardless of `b`'s signedness (the top row simply being all-zero when `b` is signed).

### Per-weight compression (three 8:2)

The three weights are reduced independently. For each weight index `j`, the eight same-weight partial products (one per lane) are gathered and fed to an 8:2 [cpr_w_n](./cpr_w_n.md) compressor:

```systemverilog
for (j = 0; j < PP_SIZE; j++) begin : gen_weight
    logic [PP_WIDTH-1:0] col [0:LANES-1];
    for (k = 0; k < LANES; k++) begin : gen_gather
        assign col[k] = pp[k][j];        // weight-j PP from every lane
    end
    cpr_w_n #(
        .IN_WIDTH (PP_WIDTH),            // 10
        .IN_SIZE  (LANES),              // 8 → 8:2 compression
        .EXT      ($clog2(LANES) + 1),  // +4 growth bits
        .IS_SIGNED(1'b1)                // signed extension (PPs are signed)
    ) cpr_w_n_i (
        .in_i   (col),
        .sum_o  (col_sum[j]),
        .carry_o(col_carry[j])
    );
    ...
end
```

Each compressor reduces the 8 signed 10-bit rows to one carry-save pair `(col_sum[j], col_carry[j])` whose arithmetic sum equals the sum of the 8 inputs. The output width is `IN_WIDTH + EXT = 10 + 4 = 14 = CPR2_WIDTH`: the `EXT = $clog2(8) + 1 = 4` growth bits give room for the sum of eight 10-bit terms — a 13-bit magnitude (`8 · 510 = 4080 < 2^13`) plus **one guard bit**. `IS_SIGNED = 1` makes the compressor sign-extend each 10-bit partial product before adding, which is what makes the resulting `(sum, carry)` pair *sign-consistent* (see below). All three weights are compressed in parallel; the `2^(2j)` positional weight is **not** applied yet — every weight's pair is produced at base position and shifted next.

### Aligning the weight rows (sign-extend + shift)

Immediately after each per-weight compressor, its two carry-save rows are sign-extended to the final width and shifted into their `2^(2j)` column:

```systemverilog
assign final_in[2*j+0] = FINAL_IN'($signed(col_sum[j]))   << (2*j);
assign final_in[2*j+1] = FINAL_IN'($signed(col_carry[j])) << (2*j);
```

Reading right to left: `$signed(col_sum[j])` reinterprets the 14-bit row as signed; `FINAL_IN'(...)` widens it to `FINAL_IN = 18` bits, and because the context is signed this **sign-extends** (copies the sign into the four new top bits); `<< (2*j)` then shifts it left into position — by `0`, `2`, `4` for `j = 0, 1, 2`. The weight-`2^4` row (`j = 2`) is shifted `<< 4`, and `14 + 4 = 18` bits exactly, which is precisely why `FINAL_IN = 18`: that shifted row is the widest thing in the datapath. The six writes (`sum` and `carry` for each of the three weights) fill `final_in[0..5]`:

| `final_in` index | Content                  | Shift  |
| ---------------- | ------------------------ | ------ |
| `0` / `1`        | weight-`2^0` sum / carry | `<< 0` |
| `2` / `3`        | weight-`2^2` sum / carry | `<< 2` |
| `4` / `5`        | weight-`2^4` sum / carry | `<< 4` |

Because each pair is sign-consistent, sign-extending and shifting it preserves its value — this is exactly the property that lets the pairs be re-aligned to different weights and later re-aligned again by `pe_array`.

### Final compression (6:2)

The six aligned 18-bit rows are reduced to the two carry-save outputs by one more [cpr_w_n](./cpr_w_n.md), this time 6:2 with **no width growth**:

```systemverilog
cpr_w_n #(
    .IN_WIDTH (FINAL_IN),    // 18
    .IN_SIZE  (2*PP_SIZE),   // 6 → 6:2 compression
    .EXT      (0),           // no growth
    .IS_SIGNED(1'b1)
) cpr_w_n_final_i (
    .in_i   (final_in),
    .sum_o  (final_sum),
    .carry_o(final_carry)
);
```

`EXT = 0` is deliberate: the six inputs are three carry-save pairs whose *combined* value is the full dot product, which already fits inside `FINAL_IN = 18` bits (established by the `<< 4` aligned row), so no extra bits are needed. The compressor sums all six rows into two 18-bit rows, `final_sum` and `final_carry`, still in carry-save.

### The 18→17-bit output and the guard bit

The 18-bit result carries the 16-bit dot-product value plus **two** guard bits; one is redundant, so the top bit of each row is dropped and the outputs are 17 bits:

```systemverilog
assign sum_o   = final_sum[OUT_WIDTH-1:0];    // final_sum[16:0]
assign carry_o = final_carry[OUT_WIDTH-1:0];  // final_carry[16:0]
```

`OUT_WIDTH = FINAL_IN - 1 = 17`. The kept 17 bits hold the 16-bit dot-product value plus **one** guard bit. The crucial invariant is that the pair stays **sign-consistent**: `signext(sum_o) + signext(carry_o)` equals the true dot product (not just modulo `2^17`). Each carry-save row therefore carries a single guard bit above the value, so its sign bit is meaningful and the pair can be sign-extended as a unit. This is what allows [pe_array](../architecture/pe_array.md) to sign-extend and re-align `dp_8`'s output when it accumulates the 16 DP8 results downstream. The testbench checks both facets on every vector: `sum_o + carry_o == Σ a_k·b_k (mod 2^17)` (**resolve**) and `signext(sum_o) + signext(carry_o) == Σ a_k·b_k` (**sign-consistent**).

### Per-operand signedness & the four sign combinations

`is_signed_a_i` and `is_signed_b_i` are independent **runtime** signals, so all four combinations `(a, b) ∈ {u,s} × {u,s}` occur. This is required by the operating modes: an operand field's **high half is signed and its low half is unsigned** — for both `a` and `b` — so a single `dp_8` must handle signed×signed, signed×unsigned, unsigned×signed, and unsigned×unsigned. The signedness flows into the leaves:

- `is_signed_a_i` reaches each `booth_r4` (and its `booth_r4_cell`s), selecting sign- vs zero-extension of the multiplicand when forming `±a` / `±2a`.
- `is_signed_b_i` reaches each `booth_r4`, selecting sign- vs zero-extension of the multiplier above its MSB before recoding — which is exactly what turns the top `2^4` partial product on (unsigned `b`) or off (signed `b`).

The per-weight and final compressors always run with `IS_SIGNED = 1`, treating their rows as signed; correctness for the unsigned cases comes from the Booth stage having already produced non-negative partial products where appropriate.

### Value range

The dot product spans a 16-bit signed range. The extremes come from the mixed-sign corners rather than signed×signed:

| Corner        | Value                     |
| ------------- | ------------------------- |
| `u × u` (max) | `8 · 255 · 15 = 30600`    |
| `u × s` (min) | `8 · 255 · (−8) = −16320` |

so the true result lives in `[−16320, +30600]` — a 16-bit signed quantity. The stage-by-stage widths are:

| Stage                         | Width | Composition                          |
| ----------------------------- | ----- | ------------------------------------ |
| Booth partial product         | 10    | `int8 · {0,±1,±2}` — exact range.    |
| Per-weight sum (8:2 cpr, ×3)  | 14    | 13-bit sum-of-8 range + 1 guard bit. |
| Weight-`2^4` aligned (`<< 4`) | 18    | 14-bit row shifted `<< 4`.           |
| Final reduce (6:2 cpr)        | 18    | six carry-save rows → two rows.      |
| Output (top bit dropped)      | 17    | 16-bit dot value + 1 guard bit.      |

The 16-bit value leaves two guard bits at 18; the redundant top bit is dropped to give the **17-bit** sign-consistent output.

Source: [dp_8.sv](../../rtl/dp_8.sv) — Testbench: [tb_dp_8.sv](../../tb/tb_dp_8.sv)
