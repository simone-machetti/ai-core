# Dot Product 8 (Bit-Plane BFP)

`dp_8_bpl_bfp` — the bit-plane build of the DP8 core. It computes the same `Σₖ aₖ·bₖ` as [dp_8](./dp_8.md) and returns it in carry-save form, but decomposes the multiplication over **the bit planes of A** instead of Booth-recoding B. Drop-in for `dp_8` inside [pe_array_bpl_bfp](./pe_array_bpl_bfp.md), with a wider operand contract and no `is_signed_b_i`.

## Purpose

Radix-4 Booth spends its work on B: three partial products per lane, each an int8 shifted/negated multiple, all of it inside the PE and therefore paid `N²` times in a grid. The bit-plane decomposition moves the B-dependent work out.

For an unsigned `a`:

```
Σₖ aₖ·bₖ  =  Σₕ 2ʰ · Σⱼ ( a₂ⱼ[h]·b₂ⱼ + a₂ⱼ₊₁[h]·b₂ⱼ₊₁ )
```

Each inner term is one of `{0, b₂ⱼ, b₂ⱼ₊₁, b₂ⱼ + b₂ⱼ₊₁}`, selected by the two lanes' bit `h`. So a lane pair contributes **one 4:1 multiplexer per bit plane** — 4 pairs × 8 planes = 32 muxes — and no multiplier logic at all.

The decisive part is where the fourth input comes from. The pair sums are a function of **B alone**, so they are precomputed once per grid column by [gate_b_n_bpl_bfp](./gate_b_n_bpl_bfp.md) inside [disp_array_b_bpl_bfp](./disp_array_b_bpl_bfp.md) and broadcast. The PE gets them for free; the adders are paid `N` times instead of `N²`.

The trade is visible in the area breakdown: selection gets much cheaper than Booth, compression gets more expensive (32 six-bit rows to reduce instead of 24 ten-bit Booth partials), and the net at the DP8 is a win — `190.63` vs `202.41` µm² standalone, **−5.8 %**; **−6.0 %** for the 16-core array measured in place. See [Intra-PE Area](../experiments/syn_pe_area.md).

## Parameters

None — fixed to the DP8 configuration (8 lanes, 8-bit A).

| Localparam                 | Value | Meaning                                                       |
| -------------------------- | ----- | ------------------------------------------------------------- |
| `LANES`                    | 8     | MAC lanes.                                                    |
| `IN_WIDTH_A`               | 8     | A element — raw int8, as the baseline.                        |
| `IN_WIDTH_B`               | 5     | **CHANGED** — B element arrives already resolved to signed.   |
| `SUM_WIDTH`                | 6     | **NEW** — precomputed pair sum width.                         |
| `NUM_COL`                  | 8     | Bit planes of A (one column each).                            |
| `MUX_WIDTH` / `MUX_SIZE`   | 6 / 4 | Selection multiplexer per lane pair per plane.                |
| `COL_WIDTH`  (`COL_EXT` 2) | 8     | Per-column 4:2 output.                                        |
| `L0_WIDTH`   (`L0_EXT` 2)  | 11    | Column-pair 4:2 output.                                       |
| `L1_WIDTH`   (`L1_EXT` 2)  | 19    | Final 9:2 output.                                             |
| `OUT_WIDTH`  (`OUT_EXT` 3) | 22    | Exported carry-save row width.                                |

## Interface

| Signal          | Dir | Width  | Description                                                                 |
| --------------- | --- | ------ | --------------------------------------------------------------------------- |
| `a_i[0:7]`      | in  | 8 each | A elements, raw int8.                                                       |
| `b_i[0:7]`      | in  | 5 each | **CHANGED** — B elements as exact signed values, from the dispatcher.       |
| `b_sum_i[0:3]`  | in  | 6 each | **NEW** — precomputed pairwise sums `b₂ⱼ + b₂ⱼ₊₁`, from the dispatcher.    |
| `is_signed_a_i` | in  | 1      | A signedness; drives the weight-2⁷ correction.                              |
| `sum_o`         | out | 22     | Carry-save sum row, sign-consistent.                                        |
| `carry_o`       | out | 22     | Carry-save carry row, sign-consistent.                                      |

**No `is_signed_b_i`** — B's signedness is resolved in [disp_array_b_bpl_bfp](./disp_array_b_bpl_bfp.md) and never reaches here. Combinational.

## Instantiation

```systemverilog
dp_8_bpl_bfp dp_8_bpl_bfp_i (
    .a_i          (a_lane),
    .b_i          (b_lane),
    .b_sum_i      (b_sum_ln),
    .is_signed_a_i(is_signed_a),
    .sum_o        (dp8_sum),
    .carry_o      (dp8_carry)
);
```

## Internal logic

### Selection: 32 multiplexers

The 5-bit B values are widened to the common `MUX_WIDTH = 6` with [ext_n](./ext_n.md) so all four mux inputs share a width, then one [mux_n](./mux_n.md) per lane pair per bit plane selects the partial:

```systemverilog
assign mux_in[0] = '0;
assign mux_in[1] = b_w[2*j+0];
assign mux_in[2] = b_w[2*j+1];
assign mux_in[3] = b_sum_i[j];
assign mux_sel   = {a_i[2*j+1][h], a_i[2*j+0][h]};
```

The select **is** the pair of A bits at plane `h` — no recoding, no shifting, no negation. This is the whole multiplier.

### The weight-2⁷ plane, for a signed A

For a signed `a`, bit 7 counts *negative*: `a = −a₇·2⁷ + Σₕ₌₀..₆ aₕ·2ʰ`. The tree naturally adds `+2⁷·S₇`, so plane 7 needs its sign flipped. Rather than build a subtractor, the column's carry-save pair is one's-complemented and a single constant row repairs the offset — a Baugh–Wooley style fold:

```systemverilog
comp_n #(.WIDTH(COL_WIDTH), .SIZE(2)) comp_n_i (
    .in_i(top_in), .neg_i(is_signed_a_i), .out_o(top_out)
);
...
assign l1_in[L1_IN_SIZE-1] = is_signed_a_i ? L1_IN_WIDTH'(1 << IN_WIDTH_A) : '0;
```

Why that constant is exactly `2⁸`: one's-complementing a two's-complement value gives `~x = −x − 1`, and **both** rows of the pair are complemented, so the pair's value becomes `−S₇ − 2`. At weight `2⁷` that contributes `−2⁷·S₇ − 2⁸`, and the `+2⁸` row cancels the offset exactly, leaving `−2⁷·S₇`. Both the complement and the constant are gated by `is_signed_a_i`, so an unsigned A costs nothing.

### Reduction: 8 → 4 → 1

| Row | Compressors                       | In → out width | What it merges                                     |
| --- | --------------------------------- | -------------- | -------------------------------------------------- |
| 0   | 8 × [cpr_w_n](./cpr_w_n.md) 4:2   | 6 → 8          | the 4 lane-pair partials of one bit plane           |
| 1   | 4 × `cpr_w_n` 4:2                 | 9 → 11         | a column pair at relative weights 2⁰/2¹             |
| 2   | 1 × `cpr_w_n` **9:2**             | 17 → 19        | the 4 nodes at 2⁰/2²/2⁴/2⁶ **plus** the constant row |

The final stage is 9:2, not 8:2, because the `+2⁸` correction rides in as a ninth row rather than needing a stage of its own. Static alignment is inline — `L1_IN_WIDTH'($signed(x)) << (SH_L1*g)`, the same idiom [dp_8](./dp_8.md) uses for its own tree; the runtime-selected [shift_n](./shift_n.md) belongs to the array above, not here.

### Guard bits and sign-consistency

The output pair must be **sign-consistent** — `signext(sum_o) + signext(carry_o)` is the dot product, not merely its low bits — because [pe_array_bpl_bfp](./pe_array_bpl_bfp.md) sign-extends and re-aligns it. `cpr_w_n` drops any carry out of its top bit, so each stage needs guard bits: sign-consistency holds once `2^(W−1) > Σ|rows|`.

Every stage carries `EXT = 2`. The **tightest** is the per-column 4:2: a resolved B element spans `[−8, 15]`, so a pair sum spans `[−16, 30]` and four rows reach `Σ|rows| ≤ 120` against `2⁷ = 128` — only **6 % of margin**. That is close enough that sign-consistency is established by simulation rather than by construction; [tb_dp_8_bpl_bfp](../testbenches/tb_dp_8_bpl_bfp.md) drives corner-biased extremes for exactly this reason. The later stages are comfortable (75 % and 66 % of their bounds).

### Why the output is padded to 22 bits

The 9:2 produces 19 bits; a final [ext_n](./ext_n.md) sign-extends the pair to 22. The pad is **free** — sign extension is rewiring, zero cells — and it sizes the tree above: with `DP8_WIDTH = 22` the array's nodes land at 31/36/44/44, which lets the L1 tap carry its node in full and keeps the L2/L3 taps in the accumulator's 40-bit format. See [pe_array_bpl_bfp](./pe_array_bpl_bfp.md).

## Verification

[tb_dp_8_bpl_bfp](../testbenches/tb_dp_8_bpl_bfp.md) checks three properties on every vector — resolve, sign-consistency, and value-equivalence against a [dp_8](./dp_8.md) fed the same raw operands — under all four signedness combinations, with lanes biased toward the extremes so the tight column bound is actually reached.

Source: [dp_8_bpl_bfp.sv](../../rtl/dp_8_bpl_bfp.sv) — Testbench: [tb_dp_8_bpl_bfp.sv](../../tb/tb_dp_8_bpl_bfp.sv) — Diagram: [dp_8_bpl_bfp](../../doc/diagrams/dp_8_bpl_bfp.excalidraw)
