# Mode 2 — Square (centered / opt)

Companion notes to [mode_2_opt.tex](./mode_2_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_2.tex](./mode_2.tex).

Mode 2 is a real **int8 × int8** dot product:

```
DP16(8×8) = Σ_{i=0..15} a_i · b_i      a = int8,  b = int8
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP16(8×8) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out**.

## Nibble split & signedness

Both operands split into hi/lo nibbles:

- `a` (int8) = `2⁴·a_H + a_L` — `a_H` signed, `a_L` **unsigned**.
- `b` (int8) = `2⁴·b^hi + b^lo` — `b^hi` signed, `b^lo` **unsigned**.

So each lane becomes **four** nibble products, and mode 2 exercises **all four** signedness combos (rows) of the general table. With the two halves (i = 0..7, 8..15) that is **8 DP8(4×4) blocks**.

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. Each block is summed over its 8 lanes and appears once per half.

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C / lane |
|---|---|---|---|---|---|---|---|
| `a_H·b^hi` | 2⁸ | 0 0 | (1) both signed | `(a_H + b^hi)²` | `a_H²` | `(b^hi)²` | 0 |
| `a_L·b^hi` | 2⁴ | 1 0 | (3) A unsigned | `((a_L−8) + b^hi)²` | `(a_L−8)²` | `(b^hi−8)²` | 64 |
| `a_H·b^lo` | 2⁴ | 0 1 | (3) B unsigned | `(a_H + (b^lo−8))²` | `(a_H−8)²` | `(b^lo−8)²` | 64 |
| `a_L·b^lo` | 2⁰ | 1 1 | (5) both unsigned | `((a_L−8) + (b^lo−8))²` | `(a_L−16)²` | `(b^lo−16)²` | 256 |

Weights come from `a·b = (2⁴a_H + a_L)(2⁴b^hi + b^lo) = 2⁸ a_H b^hi + 2⁴ a_H b^lo + 2⁴ a_L b^hi + a_L b^lo`.

## Components

`PE`, `α`, `β` are the weighted sums over all 8 blocks (4 types × 2 halves); each per-block term is taken from the table above, summed over that block's lanes:

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

Each block contributes `weight × (8 lanes × S²)`:

| block | weight | 8·S² | contribution |
|---|---|---|---|
| `a_H·b^hi` | 2⁸ | 0 | 0 |
| `a_L·b^hi` | 2⁴ | 512 | 8192 |
| `a_H·b^lo` | 2⁴ | 512 | 8192 |
| `a_L·b^lo` | 2⁰ | 2048 | 2048 |

Over both halves:

```
C = 0 + 8192 + 0 + 8192  +  8192 + 2048 + 8192 + 2048 = 36864
```

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β (unchanged from mode 1 — only the operands, weights, and `C` differ).
- Centering: flip the MSB of each **unsigned** nibble (`a_L`, `b^lo`); the signed nibbles (`a_H`, `b^hi`) are not flipped. Shared by PE and generators (dispatcher output).
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): this is what turns `a_H → a_H−8`, `b^hi → b^hi−8` (S=8 blocks) and `a_L → a_L−16`, `b^lo → b^lo−16` (S=16 blocks).
- `C = 36864` is a per-mode constant, injected once at the accumulator.
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

`a = b = 0xFF = −1` (`a_H = b^hi = −1`, `a_L = b^lo = 15`)  →  `a·b = 1`:

```
a_H·b^hi (00,f1): ½(4 − 1 − 1 + 0)       =   1 , ×2⁸ = +256
a_L·b^hi (10,f3): ½(36 − 49 − 81 + 64)   = −15 , ×2⁴ = −240
a_H·b^lo (01,f3): ½(36 − 81 − 49 + 64)   = −15 , ×2⁴ = −240
a_L·b^lo (11,f5): ½(196 − 1 − 1 + 256)   = 225 , ×1  = +225
                                            total = 1 = (−1)·(−1)  ✓
```
