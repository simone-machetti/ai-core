# Dot Product 8 (NR4SD BFP)

`dp_8_nr4sd_bfp` — the second NR4SD build of the DP8 core. It computes the same `Σₖ aₖ·bₖ` as [dp_8](./dp_8.md) and returns it in the same 20-bit sign-consistent carry-save form, but with **two** partial products per lane instead of three, from a B that arrives **already recoded** — a 2-bit NR4SD⁺ code and a 3-bit Booth window per lane, produced once per column by [disp_array_b_nr4sd_bfp](./disp_array_b_nr4sd_bfp.md). Drop-in for `dp_8` inside [pe_array_nr4sd_bfp](./pe_array_nr4sd_bfp.md) — the leaf of [top_NxN_nr4sd_bfp](../architectures/top_NxN_nr4sd_bfp.md) — with no `is_signed_b_i`.

## Purpose

[dp_8](./dp_8.md) spends its area in the compression tree, and the tree is sized by the partial-product count: 8 lanes × 3 Booth digits = 24 rows. The third digit exists only to give an *unsigned* nibble its positive top bit. Two levers remove it:

- **Hoist the recoder.** The digits of B are a function of B alone, so the recoders move out of the `N²` PEs into the `N` column dispatchers, and the DP8 keeps only the cells that turn a digit into a multiple of A.
- **Read every nibble as signed, and link the nibbles.** A lower nibble of an int8/int16 read as signed is off by `−16·b₃·A`; the dispatcher feeds its `b₃` into the nibble above as a carry-in, which gains `+b₃·A`, and the `×16` between the two DP8s in the tree cancels the two. Every nibble now needs digits for `signed(b) + c ∈ [−8, +8]` only.

Two NR4SD⁺ digits span `[−5, +10]` and miss `−6, −7, −8`, which is why the first build still needed a third digit. The hybrid of [nr4sd_r4](./nr4sd_r4.md) — NR4SD⁺ at weight 1, Booth at weight 4 — spans `[−9, +10]` in two digits, so per lane

```
aₖ · (signed(bₖ) + cₖ)  =  d₀ₖ·aₖ + 4·d₁ₖ·aₖ        d₀ ∈ {−1, 0, +1, +2},  d₁ ∈ {−2 … +2}
```

16 cells instead of 24, two per-weight compressors instead of three, a 4:2 final stage instead of a 6:2 — **204 full adders against 332**. The `−2A` multiple lives in the Booth cell only.

Measured: **144.240** µm² standalone against `dp_8`'s 202.414 (**−28.7 %**); [dp_8_bpl_b_bfp](./dp_8_bpl_b_bfp.md) is 120.198. In place, the 16-core array is **−23.9 %** against baseline-BFP (2353.97 vs 3091.57 µm²; bit-plane-B 1871.61). The first, three-digit build measured 191.275 standalone and 3160.51 in the PE — no better than baseline in context, within ABC mapping noise. See [Intra-PE Area](../experiments/syn_pe_area.md).

## Parameters

None — fixed to the DP8 configuration (8 lanes, 8-bit A, 4-bit B).

| Localparam                  | Value  | Meaning                                                                          |
| --------------------------- | ------ | -------------------------------------------------------------------------------- |
| `LANES`                     | 8      | MAC lanes.                                                                       |
| `IN_WIDTH_A`                | 8      | A element, raw int8.                                                             |
| `IN_WIDTH_B`                | 4      | B nibble width — the recoded operand.                                            |
| `NUM_DIGIT` / `PP_SIZE`     | 2      | **CHANGED** — radix-4 digits, hence partial products, per lane (3 in `dp_8`).    |
| `CODE_WIDTH` / `SEL_WIDTH`  | 2 / 3  | **NEW** — NR4SD⁺ code and Booth window widths.                                   |
| `PP_WIDTH`                  | 10     | Partial product, `int8 × {−2 … +2}`.                                             |
| `CPR2_WIDTH`                | 14     | Per-weight 8:2 output (`PP_WIDTH + $clog2(LANES) + 1`).                          |
| `FINAL_IN`                  | 16     | **CHANGED** — final-stage input, set by the `<< 2` weight-4 row (18 in `dp_8`).  |
| `FINAL_EXT` / `FINAL_WIDTH` | 2 / 18 | Final 4:2 output — 2 guard bits.                                                 |
| `OUT_EXT` / `OUT_WIDTH`     | 2 / 20 | **NEW** — sign-extension pad back to `dp_8`'s width.                             |

## Interface

| Signal           | Dir | Width  | Description                                                   |
| ---------------- | --- | ------ | ------------------------------------------------------------- |
| `a_i[0:7]`       | in  | 8 each | A elements, raw int8, from [disp_array_a](./disp_array_a.md). |
| `b_nr4sd_i[0:7]` | in  | 2 each | **NEW** — NR4SD⁺ code per lane, the weight-1 digit.           |
| `b_booth_i[0:7]` | in  | 3 each | **NEW** — Booth window per lane, the weight-4 digit.          |
| `is_signed_a_i`  | in  | 1      | A signedness; drives the extension inside every cell.         |
| `sum_o`          | out | 20     | Carry-save sum row, sign-consistent.                          |
| `carry_o`        | out | 20     | Carry-save carry row, sign-consistent.                        |

**No `is_signed_b_i`** — B's signedness is consumed in [disp_array_b_nr4sd_bfp](./disp_array_b_nr4sd_bfp.md), as "this DP8 holds the top nibble of its element", and never reaches here; `is_signed_a_i` is the only signedness signal in the DP8. Combinational.

## Instantiation

```systemverilog
dp_8_nr4sd_bfp dp_8_nr4sd_bfp_i (
    .a_i          (a_lane),
    .b_nr4sd_i    (b_nr4sd_lane),
    .b_booth_i    (b_booth_lane),
    .is_signed_a_i(is_signed_a),
    .sum_o        (dp8_sum),
    .carry_o      (dp8_carry)
);
```

## Internal logic

### Two cells per lane

The multiplier is not recoded here. Per lane, one [nr4sd_r4_cell](./nr4sd_r4_cell.md) turns the 2-bit code into `{0, +A, +2A, −A}` and one [booth_r4_cell](./booth_r4_cell.md) turns the 3-bit window into `{0, ±A, ±2A}`, both extending A per `is_signed_a_i`:

```systemverilog
for (inst = 0; inst < LANES; inst++) begin : gen_lane
    nr4sd_r4_cell #(
        .IN_WIDTH(IN_WIDTH_A)
    ) nr4sd_r4_cell_i (
        .mult_i     (a_i[inst]),
        .code_i     (b_nr4sd_i[inst]),
        .is_signed_i(is_signed_a_i),
        .pp_o       (pp[inst][0])
    );
    booth_r4_cell #(
        .IN_WIDTH(IN_WIDTH_A)
    ) booth_r4_cell_i (
        .mult_i     (a_i[inst]),
        .sel_i      (b_booth_i[inst]),
        .is_signed_i(is_signed_a_i),
        .pp_o       (pp[inst][1])
    );
end
```

`pp[inst][0]` is the weight-1 partial product, `pp[inst][1]` the weight-4 one. The digit set still tops out at `|2|`, so a partial product spans `[−256, +254]` (signed A) or `[−255, +510]` (unsigned A), inside `PP_WIDTH = 10` signed — the same width as `dp_8`'s.

### What a lane computes

The lane value is `d₀ + 4·d₁ ∈ [−9, +10]`: the nibble read as **signed** plus the cross-nibble carry the dispatcher injected. A DP8 holding a **lower** nibble of a wider element therefore returns a partial that is `16·b₃·A` too small per lane and is **not a value on its own**; the DP8 holding the nibble above carries the matching `+b₃·A`, and the tree's `×16` cancels the two. Every mode reads its tap after that merge — see [pe_array_nr4sd_bfp](./pe_array_nr4sd_bfp.md) and [booth_2pp.tex](../../doc/formulas/encodings/booth_2pp.tex).

### Reduction: 2 × 8:2 → 4:2

| Row | Compressors                     | In → out width | What it merges                                  |
| --- | ------------------------------- | -------------- | ----------------------------------------------- |
| 0   | 2 × [cpr_w_n](./cpr_w_n.md) 8:2 | 10 → 14        | the 8 same-weight partial products of one digit |
| 1   | 1 × `cpr_w_n` **4:2**           | 16 → 18        | the 2 pairs at relative weights 2⁰/2²           |

One per-weight compressor fewer than `dp_8` and a 4:2 final stage instead of its 6:2. Static alignment is inline, as in [dp_8](./dp_8.md): each pair is sign-extended to `FINAL_IN` and the weight-4 pair shifted `<< 2`:

```systemverilog
assign final_in[2*j+0] = FINAL_IN'($signed(col_sum[j]))   << (2*j);
assign final_in[2*j+1] = FINAL_IN'($signed(col_carry[j])) << (2*j);
```

`FINAL_IN` is 16 rather than 18 because `dp_8`'s `<< 4` weight-16 row — the widest thing in its datapath — no longer exists.

### Guard bits and sign-consistency

The output pair must be **sign-consistent** — `signext(sum_o) + signext(carry_o)` is the dot product, not merely its low bits — because the tree above sign-extends and re-aligns it. `cpr_w_n` drops any carry out of its top bit, so the property holds once `2^(W−1) > Σ|rows|`. The four final rows reach `2¹³` (weight 1) and `2¹⁵` (weight 4, shifted), so their absolute sum is under `2¹⁴ + 2¹⁶ = 81920` against `2¹⁷ = 131072` — `FINAL_EXT = 2` is still the minimum, as it was for `dp_8`'s six rows.

### Why the output is padded to 20 bits

The 4:2 produces 18 bits; a final [ext_n](./ext_n.md) sign-extends the pair to `dp_8`'s 20:

```systemverilog
ext_n #(
    .WIDTH    (FINAL_WIDTH),
    .SIZE     (2),
    .EXT      (OUT_EXT),
    .IS_SIGNED(1'b1)
) ext_n_out_i (
    .in_i (final_pair),
    .out_o(out_pair)
);
```

The pad is **free** (sign extension is rewiring, zero cells) and preserves sign-consistency — sign-extending both rows of a sign-consistent pair leaves their sum unchanged. It is deliberate: at 20 bits [pe_array_nr4sd_bfp](./pe_array_nr4sd_bfp.md) keeps every node width, tap width (18/29/37/38) and guard bit of [pe_array_bfp](./pe_array_bfp.md), so [acc_array_bfp](./acc_array_bfp.md) is reused as-is rather than forked the way the bit-plane builds had to fork it.

## Verification

[tb_dp_8_nr4sd_bfp](../testbenches/tb_dp_8_nr4sd_bfp.md) checks resolve and sign-consistency on every vector under both `is_signed_a_i` states, in two experiments: 2000 random `(a, b, c_in)` vectors recoded by a software model of the hybrid against `Σ aₖ·(signed(bₖ) + cₖ)`, and 2000 random raw code/window vectors against `Σ aₖ·(d₀ₖ + 4·d₁ₖ)` over the full `[−9, +10]` lane range, plus directed corners. There is no equivalence against `dp_8` at this level — a lone DP8 holding a lower nibble is off by design — it is checked one level up, in [tb_pe_array_nr4sd_bfp](../testbenches/tb_pe_array_nr4sd_bfp.md), once the nibbles have been recombined.

Source: [dp_8_nr4sd_bfp.sv](../../rtl/dp_8_nr4sd_bfp.sv) — Testbench: [tb_dp_8_nr4sd_bfp.sv](../../tb/tb_dp_8_nr4sd_bfp.sv) — Diagram: [dp_8_nr4sd_bfp](../../doc/diagrams/dp_8_nr4sd_bfp.excalidraw) — Derivation: [nr4sd_2pp.tex](../../doc/formulas/encodings/nr4sd_2pp.tex)
