# Mode 5 — Square (centered / opt)

Companion notes to [mode_5_opt.tex](./mode_5_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_5.tex](./mode_5.tex).

Mode 5 is a real **int8 × int4** dot product over **32 lanes**:

```
DP32(8×4) = Σ_{i=0..31} a_i · b_i      a = int8,  b = int4 (signed)
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP32(8×4) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

Mode 5 is Mode 1 (`DP16(8×4)`) scaled to twice the length: the 32 lanes are done as **4 groups of 8** (i = 0..7, 8..15, 16..23, 24..31), each group identical in structure to a Mode 1 half.

## Nibble split & signedness

- `a` (int8) = `2⁴·a_H + a_L` — `a_H` = signed high nibble, `a_L` = **unsigned** low nibble.
- `b` (int4) = signed, single nibble → `bu = 0` throughout (b is never biased for its own sake).

So each lane becomes two DP8(4×4) products: `a_H·b` and `a_L·b`. Across the 4 groups that is **8 DP8(4×4) blocks** (2 per group).

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. Each block is summed over its 8 lanes and appears **once per group** (× 4 groups).

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C / lane |
|---|---|---|---|---|---|---|---|
| `a_H·b` | 2⁴ | 0 0 | (1) both signed | `(a_H + b)²` | `a_H²` (4b) | `b²` (4b) | 0 |
| `a_L·b` | 2⁰ | 1 0 | (3) A unsigned | `((a_L−8) + b)²` | `(a_L−8)²` (4b) | `(b−8)²` (5b) | 64 |

Weights come from `a·b = (2⁴·a_H + a_L)·b = 2⁴·a_H·b + a_L·b`.

## Components

`PE`, `α`, `β` are the weighted sums over all 8 blocks (2 types × 4 groups); each per-block term is taken from the table above, summed over that block's 8 lanes:

```
PE = Σ_blocks  weight · Σ_lanes (PE arg)
α  = Σ_blocks  weight · Σ_lanes (α term)
β  = Σ_blocks  weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

Written out over the 4 groups g ∈ {0..7, 8..15, 16..23, 24..31}:

```
PE = Σ_g [ 2⁴·Σ_g(a_H+b)²  +  Σ_g((a_L−8)+b)² ]
α  = Σ_g [ 2⁴·Σ_g a_H²      +  Σ_g(a_L−8)²      ]
β  = Σ_g [ 2⁴·Σ_g b²        +  Σ_g(b−8)²        ]
```

- `α = PE(A,0)` (zero b): the `a_H` block gives `a_H²`, the `a_L` block gives `(a_L−8)²`.
- `β = PE(0,B)` (zero a): `a_H = 0` → `b²`; `a_L = 0` is **unsigned**, so it centers to −8 → `(b−8)²`. This is why the same `b` appears as both `b²` and `(b−8)²`, even though `b` is signed — the −8 is `a_L`'s biased zero, not a bias on `b`.

## Constant C

Each `a_L·b` block contributes `weight × (8 lanes × S²) = 1 × 8 × 64 = 512`; each `a_H·b` block contributes 0. Over the 4 groups:

```
C = 0 + 512 + 0 + 512 + 0 + 512 + 0 + 512 = 2048   (= 32 lanes × 64)
```

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β (unchanged from mode 1 — only the lane count and `C` differ).
- Centering: flip the MSB of each **unsigned** nibble (`a_L`) at the dispatcher. `b` is signed → no flip. This −8 is shared by the PE and the generators.
- `β`'s extra `−8` (giving `b−8`) is the removed `a_L`'s bias, applied **only** in the β generator as a 2-gate top-bit remap (set bit 4, flip bit 3). See [square_basics.tex](./square_basics.tex).
- `C = 2048` is a per-mode constant, injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

`a = 0xFF = −1` (`a_H = −1`, `a_L = 15`), `b = 7`  →  `a·b = −7` (per lane; ×32 lanes = −224 for an all-`(0xFF,7)` vector):

```
a_H·b : ½(36 − 1 − 49 + 0)   = −7 ,  ×2⁴ = −112     [(−1+7)²=36, (−1)²=1, 7²=49]
a_L·b : ½(196 − 49 − 1 + 64) = 105,  ×1  = +105     [(7+7)²=196, 7²=49, (−1)²=1, C=64]
                                        total = −7 = (−1)·7  ✓
```

Full-vector reconstruction (all 32 lanes `a=0xFF, b=7`): `PE`, `α`, `β` sum the 8 blocks, `C = 2048`, and `½(PE−α−β+C) = −224 = 32·(−7)`. Verified over 25k random + corner-biased vectors (`verify_mode5.py`): square args ∈ [−16,14], all reconstructions exact.
