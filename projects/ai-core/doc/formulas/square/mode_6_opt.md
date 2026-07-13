# Mode 6 — Square (centered / opt)

Companion notes to [mode_6_opt.tex](./mode_6_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_6.tex](./mode_6.tex).

Mode 6 is a real **int8 × int8** dot product over **32 lanes**:

```
DP32(8×8) = Σ_{i=0..31} a_i · b_i      a = int8,  b = int8
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP32(8×8) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

Both operands split into hi/lo nibbles; only the **single most-significant** nibble of each independent operand is signed:

- `a` (int8) = `2⁴·a_H + a_L` — `a_H` signed, `a_L` **unsigned**.
- `b` (int8) = `2⁴·b^hi + b^lo` — `b^hi` signed, `b^lo` **unsigned**.

So each lane becomes **four** nibble products, exercising all four signedness combos of the general table. The 32 lanes are processed as **4 groups of 8** (i = 0..7, 8..15, 16..23, 24..31), giving **16 DP8(4×4) blocks** (4 combos × 4 groups). No negation.

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. Each combo is summed over its 8 lanes and appears **once per group** (4 groups).

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C / lane |
|---|---|---|---|---|---|---|---|
| `a_H·b^hi` | 2⁸ | 0 0 | (1) both signed | `(a_H + b^hi)²` | `a_H²` | `(b^hi)²` | 0 |
| `a_L·b^hi` | 2⁴ | 1 0 | (3) A unsigned | `((a_L−8) + b^hi)²` | `(a_L−8)²` | `(b^hi−8)²` | 64 |
| `a_H·b^lo` | 2⁴ | 0 1 | (3) B unsigned | `(a_H + (b^lo−8))²` | `(a_H−8)²` | `(b^lo−8)²` | 64 |
| `a_L·b^lo` | 2⁰ | 1 1 | (5) both unsigned | `((a_L−8) + (b^lo−8))²` | `(a_L−16)²` | `(b^lo−16)²` | 256 |

Weights come from `a·b = (2⁴a_H + a_L)(2⁴b^hi + b^lo) = 2⁸ a_H b^hi + 2⁴ a_H b^lo + 2⁴ a_L b^hi + a_L b^lo`. Mode 6 is exactly mode 2 (int8×int8) repeated over 4 groups instead of 2, so `PE`, `α`, `β`, and `C` are all doubled relative to mode 2.

## Components

`PE`, `α`, `β` are the weighted sums over all 16 blocks (4 combos × 4 groups); each per-block term is taken from the table above, summed over that block's 8 lanes:

```
PE = Σ_blocks  weight · Σ_lanes (PE arg)
α  = Σ_blocks  weight · Σ_lanes (α term)
β  = Σ_blocks  weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

The same nibble appears squared several ways because its partner varies:

- `α`: `a_H` gives `a_H²` (paired with `b^hi`, S=0) **and** `(a_H−8)²` (paired with `b^lo`, S=8); `a_L` gives `(a_L−8)²` and `(a_L−16)²`.
- `β`: `b^hi` gives `(b^hi)²` and `(b^hi−8)²`; `b^lo` gives `(b^lo−8)²` and `(b^lo−16)²`.

The extra `−8` on a signed nibble (e.g. `a_H−8`, `b^hi−8`) is the **removed operand's biased zero** — see [square_basics.tex](./square_basics.tex) for the `α = PE(A,0)` / `β = PE(0,B)` derivation.

## Constant C

Each block contributes `weight × (8 lanes × S²)`; each combo occurs in all 4 groups:

| block | weight | 8·S² | per-group | × 4 groups |
|---|---|---|---|---|
| `a_H·b^hi` | 2⁸ | 0 | 0 | 0 |
| `a_L·b^hi` | 2⁴ | 512 | 8192 | 32768 |
| `a_H·b^lo` | 2⁴ | 512 | 8192 | 32768 |
| `a_L·b^lo` | 2⁰ | 2048 | 2048 | 8192 |

Listing all 16 blocks (group order matches the box):

```
C = 0 + 8192 + 0 + 8192 + 8192 + 2048 + 8192 + 2048
  + 0 + 8192 + 0 + 8192 + 8192 + 2048 + 8192 + 2048 = 73728
```

(= 2 × mode 2's 36864, as expected for twice the lanes.)

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β (unchanged from modes 1–2 — only the operands, weights, lane count, and `C` differ).
- Centering: flip the MSB of each **unsigned** nibble (`a_L`, `b^lo`); the signed nibbles (`a_H`, `b^hi`) are not flipped. Shared by PE and generators (dispatcher output).
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): this is what turns `a_H → a_H−8`, `b^hi → b^hi−8` (S=8 blocks) and `a_L → a_L−16`, `b^lo → b^lo−16` (S=16 blocks).
- `C = 73728` is a per-mode constant, injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

`a_i = b_i = 0xFF = −1` on all 32 lanes (`a_H = b^hi = −1`, `a_L = b^lo = 15`)  →  `a·b = 1` per lane, `Σ = 32`:

```
per lane (same as mode 2):
a_H·b^hi (00,f1): ½(4 − 1 − 1 + 0)       =   1 , ×2⁸ = +256
a_L·b^hi (10,f3): ½(36 − 49 − 81 + 64)   = −15 , ×2⁴ = −240
a_H·b^lo (01,f3): ½(36 − 81 − 49 + 64)   = −15 , ×2⁴ = −240
a_L·b^lo (11,f5): ½(196 − 1 − 1 + 256)   = 225 , ×1  = +225
                                            per-lane total = 1 = (−1)·(−1)  ✓
32 lanes → Σ = 32 ✓   (box: ½(PE − α − β + C) with C = 73728)
```
