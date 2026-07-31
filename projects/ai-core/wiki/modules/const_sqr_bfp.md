# Constant LUT (Square-BFP)

`const_sqr_bfp` — the per-DP8 constant LUT for the square-BFP datapath, the [const_sqr](./const_sqr.md) analogue for [pe_array_sqr_bfp](./pe_array_sqr_bfp.md). A small combinational table addressed by the 4-bit mode, emitting one 18-bit **signed** constant `C_j` for **each of the 16 DP8s**.

## Purpose

[const_sqr](./const_sqr.md) folds every square-reconstruction deferral into **one** tree-summed constant that the accumulator adds, because the baseline square combines `PE − α − β + C` after the reduction, once per output lane. The BFP square is different: it combines `PE_j − α_j − β_j + C_j` **per DP8, at L0**, under each block's own scale `E_j` (see [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)). So the constant is needed **per DP8, not per output lane** — this LUT supplies all 16 at once. See [BFP_imp.md](../../doc/BFP_imp.md) §9.

Each DP8's constant is the signed value its L0 node **adds**, and it folds three deferrals:

- **`+ C_cent`** — the excess-8 **centering** constant, per DP8 from its **own** signedness. Because the A int8 splits as `16·AH + AL`, the centering sum is weighted by that split: `C_cent = 16·c(nAH) + c(nAL)`, with `nAH = ~is_signed_a + ~is_signed_b` (the count of unsigned operands in the High block), `nAL = 1 + ~is_signed_b` (the Low block — the A low nibble is *always* unsigned, so the `1`), and `c(0/1/2) = 0/512/2048`.
- **`+ 4`** — the two tree-less generators ([pe_array_alpha_sqr_bfp](./pe_array_alpha_sqr_bfp.md) / [pe_array_beta_sqr_bfp](./pe_array_beta_sqr_bfp.md)) each emit `−α`/`−β` by one's-complement, deferring `−2` apiece (`−value − 2`) → `+4` per DP8.
- **block-negate (modes 10/11)** — for the DP8s whose lo mantissa bundle [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) one's-complements (the `neg` mapping → DP8 `{2,3,6,7,10,11}`), the constant must land correct **after** the block flips sign, so it takes `2 − C_cent` instead of `C_cent + 4`.

```
const_dp8 = negated ? (2 − C_cent) : (C_cent + 4)
```

The `is_signed_a/b` and `neg` patterns per mode are exactly `ctrl_sqr`'s decode, so — like [const_sqr](./const_sqr.md)'s hardcoded constants — the table is **precomputed** here rather than re-derived from decoded signals.

## Constants

Every table entry is one of a handful of distinct values, set by `C_cent` (the DP8's centering) and whether the block is negated:

| `C_cent` | `nAH` / `nAL` | `const_dp8 = C_cent + 4` | negated: `2 − C_cent` |
| -------- | ------------- | ------------------------ | --------------------- |
| 512      | 0 / 1         | 516                      | −510                  |
| 8 704    | 1 / 1         | 8 708                    | —                     |
| 10 240   | 1 / 2         | 10 244                   | −10 238               |
| 34 816   | 2 / 2         | 34 820                   | —                     |
| —        | idle          | +4 (don't-care)          | —                     |

The mode's 16 entries are the per-DP8 pattern `ctrl_sqr` produces: a real mode repeats its block signatures across the 16 DP8s (e.g. mode 8 `R16R16` cycles `516, 10244, 10244, 10244, 8708, 34820, 34820, 34820` per plane), while modes 10/11 place the negated `−510`/`−10238` on their negated DP8s. Invalid mode addresses return **0** on every DP8 (`'{default: '0}`).

The `+4` (`= C_cent 0 + 4`) is never a real active value — `nAL ≥ 1` forces `C_cent ≥ 512` for any live DP8 — so it appears **only** as the idle placeholder: modes 5/6 leave their idle DP8s at `+4`, a don't-care that [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s `zero_i` gates to 0 anyway.

## Interface

| Signal          | Dir | Width   | Description                                                          |
| --------------- | --- | ------- | ------------------------------------------------------------------- |
| `mode_i`        | in  | 4       | Mode address.                                                       |
| `const_dp8_o[0:15]` | out | 18 each | Per-DP8 signed constant `C_j` (holds `−10 238 … +34 820`).      |

## Parameters

None — fixed to the mode-constant LUT (the mode addresses and the per-mode constants are hardcoded, so the widths are not overridable). The interface widths are `localparam`s: `MODE_WIDTH = 4` (mode address), `NUM_DP8 = 16`, `DP8_WIDTH = 18` (signed per-DP8 constant, wide enough for `−10 238 … +34 820`).

## Notes

- **No register, no idle-gate** — unlike [const_sqr](./const_sqr.md), this LUT is purely combinational. The grid registers the mode **once** ahead of the LUT so the constant meets the singly-registered dispatched operands at the L0 combine, where [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s L0 register captures the whole bundle — **one register fewer** than [const_sqr](./const_sqr.md), which must reach the later accumulate stage. And the idle constants are masked by [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s `zero_i`, so no idle-gate is needed here.
- **Verification** — there is no standalone testbench; `const_sqr_bfp` was validated inside the top-level `tb_top_NxN_sqr_bfp` (gate 6), and its formula was byte-for-byte previewed by the tb-computed constant in `tb_acc_array_sqr_bfp` (gate 5) before the module was built.
- Consumer: [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) — row 6 of each L0 bundle (hi = `const_dp8_o[CX0]`, lo = `const_dp8_o[CX1]`), added into the 14:2 combine and **not** complemented by the block-negate (the negated blocks take the pre-negated `2 − C_cent` from this LUT instead).

Source: [const_sqr_bfp.sv](../../rtl/const_sqr_bfp.sv)
