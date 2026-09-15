# Shifter N (BFP)

`shift_n_bfp` — Parameterized fill-windowed variable **right** shifter: each of `SIZE` `WIDTH`-bit words is right-shifted by a shared runtime amount `amt_i` inside the `2·WIDTH` window `{fill_i, in_i}`, and the low `WIDTH` bits are returned. It is the BFP-alignment counterpart of the left-shifting weight primitive [shift_n](./shift_n.md), and the shift engine of [align_cell_bfp](./align_cell_bfp.md).

## Purpose

Applies a **data-dependent** right shift — the BFP alignment amount `|Δexp|` — to a group of words that share one amount, discarding the shifted-out LSBs (truncating toward −∞) as differently-scaled mantissas are brought to a common scale. This is the mirror image of [shift_n](./shift_n.md): that widens on a *compile-time* `SHIFT` under a select and never loses bits (it weights a reduction-tree level); this narrows in place on a *runtime* `amt_i` and loses LSBs by design (it aligns).

The distinguishing feature is the **fill window**. Instead of shifting a bare word and sign-filling from its own MSB, the module shifts the `2·WIDTH` concatenation `{fill_i, in_i}`, where the caller supplies `fill_i`. That one hook lets the same block serve two roles (see [The two uses of `fill_i`](#the-two-uses-of-fill_i)): a plain arithmetic shift, or — with `fill_i` wired to an upper neighbour's word — a distributed double-width shifter for lane fusion.

## Parameters

| Parameter   | Default               | Description                                                          |
| ----------- | --------------------- | -------------------------------------------------------------------- |
| `WIDTH`     | 8                     | Bit width of each word.                                              |
| `SIZE`      | 4                     | Number of words (all share the amount `amt_i`).                      |
| `AMT_WIDTH` | `$clog2(2·WIDTH + 1)` | Shift-amount width — wide enough to name every amount `0 … 2·WIDTH`. |
| `IS_SIGNED` | 1                     | `1` = arithmetic (sign-extend the window), `0` = logical.            |

## Interface

| Signal   | Dir | Width               | Description                                                        |
| -------- | --- | ------------------- | ------------------------------------------------------------------ |
| `in_i`   | in  | `SIZE` × `WIDTH`    | Input words (the low half of each window) — array `[0:SIZE-1]`.    |
| `fill_i` | in  | `SIZE` × `WIDTH`    | High half of each window — the bits that stream in from above.     |
| `amt_i`  | in  | `AMT_WIDTH`         | Right-shift amount, shared by all words.                           |
| `out_o`  | out | `SIZE` × `WIDTH`    | Low `WIDTH` bits of each shifted window — array `[0:SIZE-1]`.      |

## Instantiation

```systemverilog
shift_n_bfp #(
    .WIDTH     (WIDTH),
    .SIZE      (NUM_SH),
    .AMT_WIDTH (EXP_WIDTH),
    .IS_SIGNED (IS_SIGNED)
) shift_n_bfp_i (
    .in_i   (row_sel),
    .fill_i (fill_sel),
    .amt_i  (amount),
    .out_o  (sh_out)
);
```

## Internal logic

The module is purely combinational. It applies one windowed shift per word, all governed by the single shared `amt_i`; the words do not interact.

### Per-word generate loop

```systemverilog
genvar i;
generate
    for (i = 0; i < SIZE; i++) begin : gen_shift
        assign out_o[i] = IS_SIGNED
            ? WIDTH'($signed({fill_i[i], in_i[i]}) >>> amt_i)
            : WIDTH'({fill_i[i], in_i[i]} >> amt_i);
    end
endgenerate
```

Each `out_o[i]` is a function of only `in_i[i]`, `fill_i[i]`, and the common `amt_i`. Implementing the semantics `out_o = ({fill_i, in_i} >> amt_i)[WIDTH-1:0]`.

### The window and its extension

The value shifted is the `2·WIDTH`-bit concatenation `{fill_i[i], in_i[i]}` — `in_i[i]` in the low half, `fill_i[i]` in the high half. A right shift by `amt_i` pulls bits from `fill_i` down across the `WIDTH` boundary into the result, and the low `WIDTH` bits are kept. Because the window is twice the word width, a shift up to `WIDTH` still delivers a fully-defined result sourced from `fill_i`; only above `2·WIDTH` does the whole window fall away.

`IS_SIGNED` fixes what enters *above* the window (i.e. above `fill_i`) once the shift consumes it:

- **`IS_SIGNED = 1` (arithmetic):** the window is treated as `$signed` and shifted with `>>>`, so its MSB — the top bit of `fill_i` — replicates in. For a real two's-complement value this preserves sign.
- **`IS_SIGNED = 0` (logical):** an unsigned `>>` fills zeros.

This is the same compile-time signedness rationale used by [shift_n](./shift_n.md) and [ext_n](./ext_n.md): the shifter's fixed datapath position fixes whether its operands are signed.

### Saturation (amounts at or beyond `2·WIDTH`)

An `amt_i` of `2·WIDTH` or more shifts the entire window out. The result is then just the window's extension: all-sign-of-`fill_i[i][WIDTH-1]` when `IS_SIGNED`, or all-zero otherwise. `AMT_WIDTH = $clog2(2·WIDTH + 1)` is exactly wide enough to express every distinct amount `0 … 2·WIDTH` (any larger amount would be redundant — the result is already saturated), so the alignment caller can present `|Δexp|` unclamped and let it flush naturally.

### The two uses of `fill_i`

`fill_i` is what makes one block cover both alignment modes ([align_cell_bfp](./align_cell_bfp.md) chooses between them):

1. **Standalone arithmetic shift** — the caller replicates each word's own sign into `fill_i[i]` (`{WIDTH{in_i[i][WIDTH-1]}}`). The window is then a sign-extended copy of the word, and the windowed arithmetic shift equals an ordinary arithmetic right shift.
2. **Lane fusion (distributed shifter)** — the caller wires an upper (H) neighbour's word into `fill_i[i]`. The window `{neighbour, word}` is now the low `WIDTH` of a real `2·WIDTH`-bit value spanning two lanes, and bits shift correctly *across* the lane boundary. Two `WIDTH`-bit cells so fed form one `2·WIDTH` shifter, which is how a fused H/L lane pair aligns a double-width row (see [align_cell_bfp](./align_cell_bfp.md), the chain idiom).

Source: [shift_n_bfp.sv](../../rtl/shift_n_bfp.sv)
