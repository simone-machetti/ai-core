# BFP Aligner

`align_bfp` — the multi-exponent BFP aligner: a binary tree of [align_cell_bfp](./align_cell_bfp.md) cells that takes `NUM_EXP` bundles, each `SIZE` rows sharing one unsigned exponent, and re-emits every row at the single common scale `exp_o = max` of all input exponents — each row arithmetic-right-shifted by `(exp_o − its bundle's exponent)`, truncating.

## Purpose

The [align_cell_bfp](./align_cell_bfp.md) cell aligns *two* bundles; `align_bfp` generalizes that to `NUM_EXP` bundles by cascading cells in a reduction tree. All aligned rows leave as one flat vector in input order — `out_o[k*SIZE + j]` aligns with `in_i[k][j]` — so a caller reads results at the same positions it presented operands. With every exponent equal the whole tree is transparent (the pure-integer path); `NUM_EXP = 1` degenerates to a bare pass-through. The right shift is arithmetic when `IS_SIGNED`, logical otherwise.

The scheme rests on one fact: **truncating right shifts compose exactly.** Flooring a value by `a` and then by `b` equals flooring it once by `a + b`, so aligning each subtree to its *local* max and then shifting the aligned subtree again toward a *larger* max is bit-identical to a single flat shift to the global max. The tree therefore loses no more LSBs than one flat aligner would — it just spreads the work across `⌈log₂ NUM_EXP⌉` cheap two-input merges instead of one wide `NUM_EXP`-way compare.

## Parameters

| Parameter   | Default | Description                                                |
| ----------- | ------- | ---------------------------------------------------------- |
| `WIDTH`     | 20      | Row width.                                                 |
| `SIZE`      | 1       | Rows per bundle (all share one exponent).                  |
| `NUM_EXP`   | 8       | Number of bundles / exponents to align.                    |
| `EXP_WIDTH` | 8       | Exponent width (unsigned).                                 |
| `IS_SIGNED` | 1       | `1` = arithmetic (sign-fill) right shift; `0` = logical.   |

Derived `localparam`s: `TOTAL = NUM_EXP · SIZE` (total rows out) and `LEVELS = (NUM_EXP > 1) ? $clog2(NUM_EXP) : 0` (tree depth). `SIZE > 1` carries carry-save operands (e.g. a 2-row sum/carry pair) as one exponent-sharing bundle.

## Interface

| Signal  | Dir | Width                          | Description                                                       |
| ------- | --- | ------------------------------ | ----------------------------------------------------------------- |
| `in_i`  | in  | `NUM_EXP` × `SIZE` × `WIDTH`   | Input bundles — array `[0:NUM_EXP-1][0:SIZE-1]`.                  |
| `exp_i` | in  | `NUM_EXP` × `EXP_WIDTH`        | Per-bundle shared exponents — array `[0:NUM_EXP-1]`.             |
| `out_o` | out | `TOTAL` × `WIDTH`              | Aligned rows, flat, input order — `[0:TOTAL-1]`.                 |
| `exp_o` | out | `EXP_WIDTH`                    | Common scale `max` of all `exp_i`.                               |

The cells' lane-fusion chains are **tied off inside** `align_bfp` (`chain_en_i = 0`); a design needing fused wide lanes instantiates [align_cell_bfp](./align_cell_bfp.md) directly instead. As with the cell, the parent must present the **minimum** exponent on any idle/zeroed bundle so it never wins the `max`.

## Instantiation

```systemverilog
align_bfp #(
    .WIDTH    (WIDTH),
    .SIZE     (SIZE),
    .NUM_EXP  (NUM_EXP),
    .EXP_WIDTH(EXP_WIDTH),
    .IS_SIGNED(IS_SIGNED)
) align_bfp_i (
    .in_i  (in),
    .exp_i (exp),
    .out_o (out),
    .exp_o (exp_o)
);
```

## Internal logic

Two staged arrays carry the tree state: `lvl_row[0:LEVELS][0:TOTAL-1]` holds the mantissa rows at each level (`split_var` so per-row slices synthesize cleanly), and `lvl_exp[0:LEVELS][0:NUM_EXP-1]` holds each surviving group's exponent. Level `0` is just the flattened input:

```systemverilog
assign lvl_row[0][k*SIZE+j] = in_i[k][j];
assign lvl_exp[0][k]        = exp_i[k];
```

### The reduction tree

Each level `l` treats the input as `N_IN = ⌈NUM_EXP / 2^l⌉` **groups**, each group spanning `SPAN = 2^l` already-mutually-aligned original bundles. It merges adjacent groups pairwise:

```systemverilog
localparam int SPAN  = 2 ** l;
localparam int N_IN  = (NUM_EXP + SPAN - 1) / SPAN;
localparam int PAIRS = N_IN / 2;
localparam int BYE   = N_IN % 2;
```

For each pair `p`, group `G_0 = 2p` (rows `[BASE_0 +: S_0]`, `S_0 = SIZE·SPAN`) and group `G_1 = 2p+1` (rows `[BASE_1 +: S_1]`) feed one `align_cell_bfp #(.SIZE_0(S_0), .SIZE_1(S_1))`. Its `S_0 + S_1` aligned rows are written back **starting at `BASE_0`**, preserving flat order, and its `exp_o` becomes the merged group's exponent `lvl_exp[l+1][p]`. Because a group is a contiguous run of `SIZE·SPAN` rows sharing one scale, the cell aligns the whole subtree in one step.

### Non-power-of-two: the bye group and clamped pairs

`NUM_EXP` need not be a power of two, and the tree handles the remainder two ways:

- **Clamped right group** — a pair whose right group runs past `NUM_EXP` gets a *shorter* `S_1` (`S_1 = SIZE · (min(END_1, NUM_EXP) − G_1·SPAN)`). The cell's asymmetric `SIZE_0 ≠ SIZE_1` absorbs the unequal group sizes directly.
- **Bye group** — an odd `N_IN` leaves one trailing group unpaired at this level; it passes through unshifted (rows and exponent copied to `lvl_row[l+1]`/`lvl_exp[l+1]`) and pairs at a later level, when the growing `SPAN` finally reaches it.

```systemverilog
if (BYE == 1) begin : gen_bye
    assign lvl_row[l+1][BASE_B+q] = lvl_row[l][BASE_B+q];   // pass through
    assign lvl_exp[l+1][PAIRS]    = lvl_exp[l][G_B];
end
```

Spent exponent slots (`e ≥ N_OUT`) are tied to `0` each level so a partially-filled `lvl_exp` never re-enters a later `max`. After `LEVELS` levels a single group remains: `out_o[k] = lvl_row[LEVELS][k]` and `exp_o = lvl_exp[LEVELS][0]`.

For the default `NUM_EXP = 8` this is a clean 3-level binary tree — 8 → 4 → 2 → 1 groups, four then two then one `align_cell_bfp` — with no bye and no clamped pair.

## Notes

- **Equal exponents ⇒ transparent.** Every cell sees a zero difference, shifts by `0`, and passes both bundles through bit-identically — so integer modes (alignment amount `0` everywhere) run bit-exact through the same tree, the global invariant of the BFP datapath ([BFP_imp.md](../../doc/BFP_imp.md) §8).
- **Widths are unchanged.** An aligned row is only a right-shifted (smaller) version of its integer worst case, so `WIDTH` stays the integer node width; the tree adds no guard bits.
- **Where it is used.** The per-merge aligners of the BFP reduction tree ([pe_array_bfp](./pe_array_bfp.md), and the square variant [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)) and the per-lane aligners of [acc_array_bfp](./acc_array_bfp.md) are all built from the same [align_cell_bfp](./align_cell_bfp.md) cell; `align_bfp` is the standalone multi-exponent form of that cell used where a whole exponent set must collapse to one scale at once.

Source: [align_bfp.sv](../../rtl/align_bfp.sv) — Testbench: [tb_align_bfp.sv](../../tb/tb_align_bfp.sv)
