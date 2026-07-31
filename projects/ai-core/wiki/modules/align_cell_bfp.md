# BFP Alignment Cell

`align_cell_bfp` — the two-bundle building cell of the BFP aligner [align_bfp](./align_bfp.md): it takes two bundles of rows, each sharing one unsigned exponent, and re-emits both at the common scale `exp_o = max(exp_0_i, exp_1_i)` — the smaller-exponent bundle arithmetic-right-shifted, the larger passed through bit-identical. Built structurally from [sub_n_bfp](./sub_n_bfp.md), [mux_n](./mux_n.md), and one [shift_n_bfp](./shift_n_bfp.md).

## Purpose

This is the hardware realization of the BFP two-operand alignment contract ([BFP_imp.md](../../doc/BFP_imp.md) §8): given `(rows_0, exp_0)` and `(rows_1, exp_1)`, bring both to `E = max(exp_0, exp_1)` by arithmetic-right-shifting the smaller-scale bundle by `|exp_0 − exp_1|` (truncating toward −∞), leaving row positions unchanged. The aligned rows leave as one vector in **input order** — `out_o[0 +: SIZE_0]` from `in_0_i`, `out_o[SIZE_0 +: SIZE_1]` from `in_1_i` — so a caller can wire the cell inline without re-permuting.

The whole cell is one comparison steering one shifter. [sub_n_bfp](./sub_n_bfp.md) turns the two exponents into a sign and a magnitude; the **sign** (`msb`) drives every select — max-exponent pick, per-slot row swap, per-row output un-swap — and the **magnitude** (`amount`) is the single shift the shifter applies. Because a small-to-large right shift is always in one direction, no bidirectional shifter is needed: the muxes route whichever bundle is smaller *into* the fixed-direction [shift_n_bfp](./shift_n_bfp.md) and route the result back out.

**Two invariants the cell relies on the parent to keep** ([align_bfp](./align_bfp.md) does both):

- On equal exponents the difference is `0`, so bundle 1 traverses the shifter with amount `0` and the cell is fully transparent — the pure-integer path, bit-exact to no aligner at all.
- An idle/zeroed bundle must arrive at the **minimum** exponent so it never wins the `max` and pulls real data down.

## Parameters

| Parameter   | Default | Description                                                     |
| ----------- | ------- | --------------------------------------------------------------- |
| `WIDTH`     | 20      | Row width.                                                      |
| `SIZE_0`    | 2       | Number of rows in bundle 0 (all share `exp_0_i`).              |
| `SIZE_1`    | 2       | Number of rows in bundle 1 (all share `exp_1_i`).             |
| `EXP_WIDTH` | 8       | Exponent width (unsigned).                                      |
| `IS_SIGNED` | 1       | `1` = arithmetic (sign-fill) right shift; `0` = logical.       |

`SIZE_0` and `SIZE_1` may differ — the tree pairs unequal-size groups at its boundaries (see [align_bfp](./align_bfp.md)). Derived `localparam`s: `NUM_SH = max(SIZE_0, SIZE_1)` (shifter slots), `MIN_SH = min(SIZE_0, SIZE_1)` (slots present in *both* bundles), `SIZE_OUT = SIZE_0 + SIZE_1`.

## Interface

| Signal       | Dir | Width                | Description                                                              |
| ------------ | --- | -------------------- | ------------------------------------------------------------------------ |
| `in_0_i`     | in  | `SIZE_0` × `WIDTH`   | Bundle 0 rows — array `[0:SIZE_0-1]`.                                    |
| `exp_0_i`    | in  | `EXP_WIDTH`          | Bundle 0 shared exponent.                                                |
| `in_1_i`     | in  | `SIZE_1` × `WIDTH`   | Bundle 1 rows — array `[0:SIZE_1-1]`.                                    |
| `exp_1_i`    | in  | `EXP_WIDTH`          | Bundle 1 shared exponent.                                                |
| `chain_en_i` | in  | 1                    | Lane-fusion enable: `1` takes the shifter fill from `chain_*_i`.        |
| `chain_0_i`  | in  | `SIZE_0` × `WIDTH`   | Fill rows for bundle 0 (H neighbour's rows in a fused pair).             |
| `chain_1_i`  | in  | `SIZE_1` × `WIDTH`   | Fill rows for bundle 1.                                                  |
| `chain_0_o`  | out | `SIZE_0` × `WIDTH`   | Raw `in_0_i` forwarded to the L neighbour of a fused pair.               |
| `chain_1_o`  | out | `SIZE_1` × `WIDTH`   | Raw `in_1_i` forwarded to the L neighbour.                               |
| `out_o`      | out | `SIZE_OUT` × `WIDTH` | Aligned rows, input order — `[0 +: SIZE_0]` from 0, `[SIZE_0 +: SIZE_1]` from 1. |
| `exp_o`      | out | `EXP_WIDTH`          | Common scale `max(exp_0_i, exp_1_i)`.                                    |

For standalone use tie `chain_en_i` low and `chain_0_i`/`chain_1_i` to zero; the `chain_*_o` outputs may be left open.

## Instantiation

```systemverilog
align_cell_bfp #(
    .WIDTH    (WIDTH),
    .SIZE_0   (S_0),
    .SIZE_1   (S_1),
    .EXP_WIDTH(EXP_WIDTH),
    .IS_SIGNED(IS_SIGNED)
) align_cell_bfp_i (
    .in_0_i    (cell_in_0), .exp_0_i(exp_0),
    .in_1_i    (cell_in_1), .exp_1_i(exp_1),
    .chain_en_i(1'b0),
    .chain_0_i (zero_0), .chain_1_i(zero_1),
    .chain_0_o (), .chain_1_o(),
    .out_o     (cell_out), .exp_o(exp_o)
);
```

## Internal logic

The datapath is: **one `sub_n_bfp` compare → a swap network of `mux_n`s → one `shift_n_bfp` on all `NUM_SH` slots → an un-swap network of `mux_n`s.** Every select is the same bit — `msb`, the sub's `sign_o`.

### The compare and the max

```systemverilog
sub_n_bfp #(.WIDTH(EXP_WIDTH)) sub_n_bfp_i (
    .in_0_i(exp_0_i), .in_1_i(exp_1_i), .abs_o(amount), .sign_o(msb)
);
```

`msb = 1` exactly when `exp_1_i > exp_0_i` — i.e. bundle 0 is the smaller-scale one and must shift. The exponent output is a two-way pick with the same select: `mux_n(EXP_WIDTH, 2)` on `{exp_0_i, exp_1_i}` returns `exp_1_i` when `msb`, else `exp_0_i` — which is `max(exp_0_i, exp_1_i)`.

### Swap into the shifter

For every slot present in **both** bundles (`s < MIN_SH`) a row-swap mux picks the *smaller* bundle's row to shift:

```systemverilog
assign row_in[0] = in_1_i[s];   // msb = 0 → shift bundle 1 (bundle 0 ≥ bundle 1)
assign row_in[1] = in_0_i[s];   // msb = 1 → shift bundle 0 (bundle 1 larger)
mux_n #(.WIDTH(WIDTH), .SIZE(2)) mux_n_row_i (.in_i(row_in), .sel_i(msb), .out_o(row_sel[s]));
```

so `row_sel[s]` always carries the row that will be right-shifted. A parallel mux picks the matching fill row from `chain_0_i`/`chain_1_i`. The fill actually driven into the shifter is then chosen by `chain_en_i`:

```systemverilog
assign fill_sel[s] = chain_en_i ? chain_sel : {WIDTH{IS_SIGNED & row_sel[s][WIDTH-1]}};
```

Standalone (`chain_en_i = 0`) the fill is the shifted row's own sign (arithmetic shift) or zero; fused it is the neighbour's row (see [Lane fusion](#lane-fusion)). All `NUM_SH` slots then go through one shifter at the common `amount`:

```systemverilog
shift_n_bfp #(.WIDTH(WIDTH), .SIZE(NUM_SH), .AMT_WIDTH(EXP_WIDTH), .IS_SIGNED(IS_SIGNED))
    shift_n_bfp_i (.in_i(row_sel), .fill_i(fill_sel), .amt_i(amount), .out_o(sh_out));
```

### Asymmetric bundles skip the swap mux

When `SIZE_0 ≠ SIZE_1`, slots `s ∈ [MIN_SH, NUM_SH)` exist in only the larger bundle, so there is nothing to swap against — that bundle's row wires straight to the shifter (`gen_wire_0`/`gen_wire_1`):

```systemverilog
end else if (SIZE_0 > SIZE_1) begin : gen_wire_0
    assign row_sel[s] = in_0_i[s];
    assign chain_sel  = chain_0_i[s];
```

Those extra slots' shifted values are only ever *read* when the larger-size bundle is the one shifting; when it is instead the max, its rows pass through and `sh_out` for those slots is ignored. A mux against a constant zero would be redundant — dropping it is the cheaper equivalent.

### Un-swap to input order

Each output row is a two-way pick between "this bundle's raw row" (it was the max → passthrough) and "the shifted slot" (it was smaller → shifted):

```systemverilog
// bundle 0 outputs: passthrough when msb = 0, shifted when msb = 1
assign out_in[0] = in_0_i[r];   assign out_in[1] = sh_out[r];
mux_n #(...) mux_n_out_i (.in_i(out_in), .sel_i(msb), .out_o(out_o[r]));
// bundle 1 outputs: shifted when msb = 0, passthrough when msb = 1
assign out_in[0] = sh_out[r];   assign out_in[1] = in_1_i[r];
mux_n #(...) mux_n_out_i (.in_i(out_in), .sel_i(msb), .out_o(out_o[SIZE_0+r]));
```

The larger bundle emerges **bit-identical** (never routed through the shifter), and the smaller emerges truncated by exactly `|Δexp|`.

### Lane fusion

For a fused H/L lane pair (the [gate_b_n](./gate_b_n.md) carry idiom, two crossing buses running opposite directions), the two cells share one `2·WIDTH` shift. Each cell forwards its raw rows down the chain (`chain_0_o[r] = in_0_i[r]`, `chain_1_o[r] = in_1_i[r]`), and the L cell — with `chain_en_i` set — takes those as its shifter fill instead of sign replication, so the window `{fill, row}` in [shift_n_bfp](./shift_n_bfp.md) spans both lanes and bits shift correctly across the boundary. A fused pair **must** receive equal exponents on both cells (they align the same node); [align_bfp](./align_bfp.md) ties the chains off, while a consumer that needs a wide row (e.g. [acc_array_bfp](./acc_array_bfp.md)'s fused lanes) instantiates the cells directly and wires the chain.

## Notes

- **Truncation is LSB-side and one-directional** — the smaller bundle floors toward −∞ by `|Δexp|`; the datapath keeps its integer widths because an aligned addend is only a right-shifted (smaller) version of its integer worst case ([BFP_imp.md](../../doc/BFP_imp.md) §8). No rounding here; the single rounding lives at the output quantization stage (§10).
- **Carry-save use** — a "row" is just a `WIDTH`-bit bus, so a carry-save operand is a 2-row bundle (sum + carry) sharing one exponent; each row floors independently. This is how the tree cells ([pe_array_bfp](./pe_array_bfp.md)) and the accumulator cells ([acc_array_bfp](./acc_array_bfp.md)) align carry-save pairs with the same primitive.
- Consumers: [align_bfp](./align_bfp.md) (tree of these cells), and directly-instantiated fused pairs in [acc_array_bfp](./acc_array_bfp.md) / [pe_array_sqr_bfp](./pe_array_sqr_bfp.md).

Source: [align_cell_bfp.sv](../../rtl/align_cell_bfp.sv) — Testbench: [tb_align_cell_bfp.sv](../../tb/tb_align_cell_bfp.sv) — Diagram: [align_cell_bfp](../../doc/diagrams/align_cell_bfp.excalidraw)
