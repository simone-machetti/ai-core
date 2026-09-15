# Booth Radix-4

`booth_r4` — radix-4 Booth partial-product generator with per-operand runtime signedness: recodes the multiplier into overlapping 3-bit windows and emits `PP_SIZE` partial products of the multiplicand.

## Purpose

Produces the radix-4 Booth partial products of `a_i × b_i` — `PP_SIZE = IN_WIDTH_B/2 + 1` products, each `IN_WIDTH_A + 2` bits wide — roughly halving the partial-product count versus a plain shift-and-add array. The multiplier `b_i` (the recoded operand) should carry the **narrower** operand so the fewest windows, hence the fewest partial products, are generated (e.g. the 4-bit operand of an 8×4 multiply). Signedness is per operand and runtime: `is_signed_a_i` controls how the multiplicand is extended, `is_signed_b_i` controls how the multiplier is extended before recoding.

## Parameters

| Parameter    | Default | Description                                                        |
| ------------ | ------- | ------------------------------------------------------------------ |
| `IN_WIDTH_A` | 8       | Bit width of the multiplicand `a_i`.                               |
| `IN_WIDTH_B` | 4       | Bit width of the multiplier `b_i` (recoded; the narrower operand). |

Derived: `PP_SIZE = IN_WIDTH_B/2 + 1` (partial-product count), `PP_WIDTH = IN_WIDTH_A + 2` (per-PP width), `MULT_EXT_WIDTH = 2·PP_SIZE + 1` (width of the extended multiplier). `PP_SIZE` carries the count needed for the **unsigned** case — one more window than a signed-only recoder would need (see below).

## Interface

| Signal          | Dir | Width                  | Description                                                        |
| --------------- | --- | ---------------------- | ------------------------------------------------------------------ |
| `a_i`           | in  | `IN_WIDTH_A`           | Multiplicand — fanned out to every cell.                           |
| `b_i`           | in  | `IN_WIDTH_B`           | Multiplier — recoded into `PP_SIZE` Booth selectors.               |
| `is_signed_a_i` | in  | 1                      | Multiplicand extension: `1` = signed, `0` = unsigned.              |
| `is_signed_b_i` | in  | 1                      | Multiplier extension: `1` = signed, `0` = unsigned.                |
| `pp_o`          | out | `PP_SIZE` × `PP_WIDTH` | Partial products — unpacked array `pp_o[0:PP_SIZE-1]`, unweighted. |

`is_signed_a_i` and `is_signed_b_i` are **runtime** signals, not parameters: both follow the datapath operating mode ([dp_8](./dp_8.md)) and can change cycle to cycle.

## Instantiation

```systemverilog
booth_r4 #(
    .IN_WIDTH_A(8),
    .IN_WIDTH_B(4)
) booth_r4_i (
    .a_i          (a),
    .b_i          (b),
    .is_signed_a_i(is_signed_a),
    .is_signed_b_i(is_signed_b),
    .pp_o         (pp)   // pp[0:PP_SIZE-1], each PP_WIDTH bits
);
```

## Internal logic

Purely combinational — no clock, no storage. The module extends the multiplier, slices it into overlapping 3-bit windows, and drives one [booth_r4_cell](./booth_r4_cell.md) per window against the shared multiplicand.

### Radix-4 recoding

Radix-4 Booth looks at the multiplier two bits at a time, with a 1-bit overlap into the next-lower pair, and recodes each group into one signed digit in `{-2, -1, 0, +1, +2}`. Grouping two bits (radix 4) means only `⌈n/2⌉`-ish windows are needed instead of `n`, so half as many partial products.

The multiplier is first widened, with a trailing zero appended below the LSB and `ext_bit` filling above the MSB:

```systemverilog
localparam int MULT_EXT_WIDTH = 2 * PP_SIZE + 1;

assign ext_bit  = is_signed_b_i ? b_i[IN_WIDTH_B-1] : 1'b0;
assign mult_ext = {{(MULT_EXT_WIDTH-IN_WIDTH_B-1){ext_bit}}, b_i, 1'b0};
```

- The trailing `1'b0` is the phantom bit `b[-1]` that Booth recoding needs at the bottom.
- `ext_bit` extends `b_i` above its MSB: it is the sign bit `b_i[MSB]` when `is_signed_b_i`, otherwise `0`. This is the single knob that makes the multiplier signed or unsigned.

`mult_ext` is then sliced into `PP_SIZE` overlapping 3-bit selectors, each stepping by 2 bits:

```systemverilog
for (i = 0; i < PP_SIZE; i++) begin : gen_booth
    logic [2:0] sel;
    assign sel = mult_ext[2*i +: 3];
    ...
end
```

Because `mult_ext = {…, b, 1'b0}`, window `i` is `sel = {b[2i+1], b[2i], b[2i-1]}` (with `b[-1] = 0`). For the default `IN_WIDTH_B = 4` (`PP_SIZE = 3`, `MULT_EXT_WIDTH = 7`, `mult_ext = {ext, ext, b3, b2, b1, b0, 0}`):

| `i` | slice `mult_ext[2i +: 3]` | selector bits    |
| --- | ------------------------- | ---------------- |
| 0   | `[2:0]`                   | `{b1, b0, 0}`    |
| 1   | `[4:2]`                   | `{b3, b2, b1}`   |
| 2   | `[6:4]`                   | `{ext, ext, b3}` |

### Partial-product cell

Each selector drives one [booth_r4_cell](./booth_r4_cell.md), which decodes the 3-bit window into one of `{0, ±1×, ±2×}` of the multiplicand:

```systemverilog
booth_r4_cell #(
    .IN_WIDTH(IN_WIDTH_A)
) booth_r4_cell_i (
    .mult_i     (a_i),
    .sel_i      (sel),
    .is_signed_i(is_signed_a_i),
    .pp_o       (pp_o[i])
);
```

The recode digit is `d = -2·sel[2] + sel[1] + sel[0]`, giving the table (see [booth_r4_cell](./booth_r4_cell.md) for the matching `case`):

| `sel` | digit `d` | Operation | `sel` | digit `d` | Operation |
| ----- | --------- | --------- | ----- | --------- | --------- |
| `000` | `0`       | 0         | `100` | `-2`      | `-2×`     |
| `001` | `+1`      | `+1×`     | `101` | `-1`      | `-1×`     |
| `010` | `+1`      | `+1×`     | `110` | `-1`      | `-1×`     |
| `011` | `+2`      | `+2×`     | `111` | `0`       | 0         |

The multiplicand is sign- or zero-extended inside the cell per `is_signed_a_i`, and each `pp_o[i]` is `PP_WIDTH = IN_WIDTH_A + 2` bits — the two spare MSBs hold the `2×` shift and carry the sign of the negated multiples.

### Weighting

The module emits the partial products **unweighted** — `pp_o[i]` is the raw `d_i × a` value. Window `i` steps 2 bits up the multiplier, so its digit has radix-4 place value `4^i = 2^(2·i)`. The consumer ([dp_8](./dp_8.md)) reconstructs the product by shifting each PP left by `2·i` before summing:

```
a × b = Σ  pp_o[i] << (2·i)     for i = 0 … PP_SIZE-1
```

Keeping the shift out of this block lets the downstream adder tree align the products however it likes; `booth_r4` only decides *what* each partial product is, not *where* it sits.

### Per-operand signedness and the extra unsigned PP

`is_signed_a_i` and `is_signed_b_i` are independent, so any signed/unsigned mix of operands is supported at runtime.

- **Multiplicand (`is_signed_a_i`)** — handled entirely inside each cell, choosing sign- vs zero-extension when it forms `±a` / `±2a`.
- **Multiplier (`is_signed_b_i`)** — handled by `ext_bit`, which fills the bits above `b_i[MSB]` in `mult_ext`.

The **top** window, `i = PP_SIZE-1`, is where the two multiplier modes diverge. For the default it is `sel = {ext, ext, b3}`:

- **Signed `b`** (`ext_bit = b3`): the window is `{b3, b3, b3}` = `000` or `111`, both of which recode to `0`. The top partial product **vanishes** — the sign of `b` is already accounted for by the `-2·sel[2]` term of the next-lower digit, so no extra product is needed.
- **Unsigned `b`** (`ext_bit = 0`): the window is `{0, 0, b3}` = `000` or `001`, recoding to `0` or `+1×`. This emits a final `{0, +a}` partial product that supplies the positive place value of the top multiplier bit `b3`, which the signed recoding would otherwise have treated as a sign.

Because the unsigned case needs this one extra product while the signed case leaves it at zero, the count is sized for the worst case: `PP_SIZE = IN_WIDTH_B/2 + 1`. For a signed multiplier that top slot is always `0` and contributes nothing to the sum.

Source: [booth_r4.sv](../../rtl/booth_r4.sv) — Testbench: [tb_booth_r4.sv](../../tb/tb_booth_r4.sv)
