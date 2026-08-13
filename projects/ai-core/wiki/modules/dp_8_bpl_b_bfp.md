# Dot Product 8 (Bit-Plane-B BFP)

`dp_8_bpl_b_bfp` — the second bit-plane build of the DP8 core. It computes the same `Σₖ aₖ·bₖ` as [dp_8](./dp_8.md) and returns it in carry-save form, but decomposes the multiplication over **the bit planes of B** instead of the bit planes of A. Drop-in for `dp_8` inside [pe_array_bpl_b_bfp](./pe_array_bpl_b_bfp.md), with the operand roles of [dp_8_bpl_a_bfp](./dp_8_bpl_a_bfp.md) exchanged and no `is_signed_a_i`.

## Purpose

[dp_8_bpl_a_bfp](./dp_8_bpl_a_bfp.md) established the lever: replace Booth recoding with a 4:1 multiplexer per lane pair per bit plane, and hoist the pair sums — a function of one operand alone — into the shared dispatcher. This build applies the identity the other way round.

For an unsigned `b`:

```
Σₖ aₖ·bₖ  =  Σₕ 2ʰ · Σⱼ ( a₂ⱼ·b₂ⱼ[h] + a₂ⱼ₊₁·b₂ⱼ₊₁[h] )
```

Each inner term is one of `{0, a₂ⱼ, a₂ⱼ₊₁, a₂ⱼ + a₂ⱼ₊₁}`, selected by the two lanes' bit `h` **of B**. The rule that decides which way to run the decomposition is simple:

> **Index with the narrow operand, tabulate the wide one.** The partial-product count is (index width) × (lane groups).

B is 4 bits and A is 8, so indexing on B gives **4 bit planes instead of 8** — 4 pairs × 4 planes = **16 multiplexers**, half of bit-plane A's 32. The muxes are wider (10-bit words carrying tabulated A instead of 6-bit words carrying tabulated B), so selection is roughly a wash; the compression tree is what halves, and that is where the DP8 spends its area.

Measured: **120.198** µm² standalone against `dp_8`'s 202.414 (**−40.6 %**) and `dp_8_bpl_a_bfp`'s 190.634 (**−36.9 %**) — the smallest DP8 in the project, below even [dp_8_sqr](./dp_8_sqr.md) at 129.427. In place, the 16-core array is **−39.5 %** against baseline-BFP (1871.61 vs 3091.57 µm²). See [Intra-PE Area](../experiments/syn_pe_area.md).

## Parameters

None — fixed to the DP8 configuration (8 lanes, 8-bit A, 4-bit B).

| Localparam                        | Value  | Meaning                                                     |
| --------------------------------- | ------ | ----------------------------------------------------------- |
| `LANES`                           | 8      | MAC lanes.                                                  |
| `IN_WIDTH_A`                      | 9      | **CHANGED** — A element arrives already resolved to signed. |
| `SUM_WIDTH`                       | 10     | **NEW** — precomputed A pair-sum width.                     |
| `IN_WIDTH_B`                      | 4      | **CHANGED** — B element, raw int4.                          |
| `NUM_BLK`                         | 4      | Lane pairs.                                                 |
| `NUM_PLANE`                       | 4      | Bit planes of B (one column each) — **8 in bit-plane A**.   |
| `MUX_WIDTH` / `MUX_SIZE`          | 10 / 4 | Selection multiplexer per lane pair per plane.              |
| `COL_WIDTH`  (`COL_EXT` 3)        | 13     | Per-plane 4:2 output.                                       |
| `SH_L1` / `L1_WIDTH` (`L1_EXT` 2) | 1 / 16 | Plane-pair 4:2 output at relative weights 2⁰/2¹.            |
| `SH_L2` / `L2_WIDTH` (`L2_EXT` 2) | 2 / 20 | Final 5:2 output at relative weights 2⁰/2².                 |
| `OUT_WIDTH`  (`OUT_EXT` 2)        | 22     | Exported carry-save row width.                              |

## Interface

| Signal          | Dir | Width   | Description                                                             |
| --------------- | --- | ------- | ----------------------------------------------------------------------- |
| `a_i[0:7]`      | in  | 9 each  | **CHANGED** — A elements as exact signed values, from the dispatcher.   |
| `a_sum_i[0:3]`  | in  | 10 each | **NEW** — precomputed pairwise sums `a₂ⱼ + a₂ⱼ₊₁`, from the dispatcher. |
| `b_i[0:7]`      | in  | 4 each  | **CHANGED** — B elements, raw int4 straight from `disp_array_b`.        |
| `is_signed_b_i` | in  | 1       | B signedness; drives the weight-2³ correction.                          |
| `sum_o`         | out | 22      | Carry-save sum row, sign-consistent.                                    |
| `carry_o`       | out | 22      | Carry-save carry row, sign-consistent.                                  |

**No `is_signed_a_i`** — A's signedness is resolved in [disp_array_a_bpl_b_bfp](./disp_array_a_bpl_b_bfp.md) and never reaches here. Combinational.

## Instantiation

```systemverilog
dp_8_bpl_b_bfp dp_8_bpl_b_bfp_i (
    .a_i          (a_lane),
    .a_sum_i      (a_sum_ln),
    .b_i          (b_lane),
    .is_signed_b_i(is_signed_b),
    .sum_o        (dp8_sum),
    .carry_o      (dp8_carry)
);
```

## Internal logic

### Selection: 16 multiplexers

The 9-bit A values are widened to the common `MUX_WIDTH = 10` with [ext_n](./ext_n.md) so all four mux inputs share a width — the pair sums already arrive at 10 — then one [mux_n](./mux_n.md) per lane pair per bit plane selects the partial:

```systemverilog
assign mux_in[0] = '0;
assign mux_in[1] = a_w[2*j+0];
assign mux_in[2] = a_w[2*j+1];
assign mux_in[3] = a_sum_i[j];
assign mux_sel   = {b_i[2*j+1][h], b_i[2*j+0][h]};
```

The select **is** the pair of B bits at plane `h`, taken raw from [disp_array_b](./disp_array_b.md) — no recoding, no shifting, no negation, and no widening of B at all. This is the whole multiplier.

### The weight-2³ plane, for a signed B

For a signed `b`, bit 3 counts *negative*: `b = −b₃·2³ + Σₕ₌₀..₂ bₕ·2ʰ`. The same Baugh–Wooley fold as the A build, one plane lower:

```systemverilog
comp_n #(.WIDTH(COL_WIDTH), .SIZE(2)) comp_n_i (
    .in_i(top_in), .neg_i(is_signed_b_i), .out_o(top_out)
);
...
assign l2_in[L2_IN_SIZE-1] = is_signed_b_i ? L2_IN_WIDTH'(1 << IN_WIDTH_B) : '0;
```

One's-complementing both rows of the pair gives `−S₃ − 2`; at weight `2³` that is `−2³·S₃ − 2⁴`, and the `+2⁴` row cancels the offset exactly. Both the complement and the constant are gated by `is_signed_b_i`, so an unsigned B costs nothing.

### Reduction: 4 → 2 → 1

| Row | Compressors                     | In → out width | What it merges                                 |
| --- | ------------------------------- | -------------- | ---------------------------------------------- |
| 0   | 4 × [cpr_w_n](./cpr_w_n.md) 4:2 | 10 → 13        | the 4 lane-pair partials of one bit plane      |
| 1   | 2 × `cpr_w_n` 4:2               | 14 → 16        | a plane pair at relative weights 2⁰/2¹         |
| 2   | 1 × `cpr_w_n` **5:2**           | 18 → 20        | the 2 nodes at 2⁰/2² **plus** the constant row |

Half the rows of the A build at every level — 4 column compressors instead of 8, 2 merges instead of 4, and a **5:2** final stage instead of a 9:2, the `+2⁴` correction again riding in as the last row rather than needing a stage of its own. Static alignment is inline (`L1_IN_WIDTH'($signed(x)) << SH_L1`), as in [dp_8](./dp_8.md); the runtime-selected [shift_n](./shift_n.md) belongs to the array above.

### Guard bits and sign-consistency

The output pair must be **sign-consistent** — `signext(sum_o) + signext(carry_o)` is the dot product, not merely its low bits — because [pe_array_bpl_b_bfp](./pe_array_bpl_b_bfp.md) sign-extends and re-aligns it. `cpr_w_n` drops any carry out of its top bit, so sign-consistency holds once `2^(W−1) > Σ|rows|`.

Unlike the A build this margin is comfortable. A resolved A element spans `[−128, 255]`, so a pair sum spans `[−256, 510]` and the per-plane 4:2 reaches `Σ|rows| ≤ 2040` against `2¹² = 4096` — **50 % of the bound**, where [dp_8_bpl_a_bfp](./dp_8_bpl_a_bfp.md) sat at 6 %. The tight quantity here is instead the multiplexer word itself: 10 bits hold `[−512, 511]` and the pair sum reaches 510, which is why [gate_n_bpl_bfp](./gate_n_bpl_bfp.md) emits sums at `WIDTH+2` rather than `WIDTH+1`.

### Why the output is padded to 22 bits

The 5:2 produces 20 bits; a final [ext_n](./ext_n.md) sign-extends the pair to 22 — the same `DP8_WIDTH` the A build reaches from 19. The pad is **free** (sign extension is rewiring, zero cells) and it is deliberate: at 22 bits the array's nodes land at 31/36/44/44 and its taps at 18/36/40/40, exactly the bit-plane A geometry, so both arrays share one [acc_array_bpl_bfp](./acc_array_bpl_bfp.md). See [pe_array_bpl_b_bfp](./pe_array_bpl_b_bfp.md).

## Verification

[tb_dp_8_bpl_b_bfp](../testbenches/tb_dp_8_bpl_b_bfp.md) checks three properties on every vector — resolve, sign-consistency, and value-equivalence against a [dp_8](./dp_8.md) fed the same raw operands — under all four signedness combinations, with the bench reproducing the dispatcher's operand preparation so the DUT is exercised through the contract it sees in the grid.

Source: [dp_8_bpl_b_bfp.sv](../../rtl/dp_8_bpl_b_bfp.sv) — Testbench: [tb_dp_8_bpl_b_bfp.sv](../../tb/tb_dp_8_bpl_b_bfp.sv) — Diagram: [dp_8_bpl_b_bfp](../../doc/diagrams/dp_8_bpl_b_bfp.excalidraw) — Derivation: [basics.tex](../../doc/formulas/bit-plane-bfp/basics.tex)
