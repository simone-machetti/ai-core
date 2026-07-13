# Mode 1 — Square (centered / opt)

Companion notes to [mode_1_opt.tex](./mode_1_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_1.tex](./mode_1.tex).

Mode 1 is a real **int8 × int4** dot product:

```
DP16(8×4) = Σ_{i=0..15} a_i · b_i      a = int8,  b = int4 (signed)
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP16(8×4) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

- `a` (int8) = `2⁴·a_H + a_L` — `a_H` = signed high nibble, `a_L` = **unsigned** low nibble.
- `b` (int4) = signed, single nibble → `bu = 0` throughout (b is never biased for its own sake).

So each lane becomes two DP8(4×4) products: `a_H·b` and `a_L·b`. The 16-lane dot product is done as two halves (i = 0..7, 8..15), giving **4 DP8(4×4) blocks**.

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. Each block is summed over its 8 lanes and appears once per half.

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C / lane |
|---|---|---|---|---|---|---|---|
| `a_H·b` | 2⁴ | 0 0 | (1) both signed | `(a_H + b)²` | `a_H²` (4b) | `b²` (4b) | 0 |
| `a_L·b` | 2⁰ | 1 0 | (3) A unsigned | `((a_L−8) + b)²` | `(a_L−8)²` (4b) | `(b−8)²` (5b) | 64 |

## Components

```
PE = 2⁴·Σ_{0..7}(a_H+b)²  +  Σ_{0..7}((a_L−8)+b)²  +  2⁴·Σ_{8..15}(a_H+b)²  +  Σ_{8..15}((a_L−8)+b)²
α  = 2⁴·Σ_{0..7} a_H²     +  Σ_{0..7}(a_L−8)²      +  2⁴·Σ_{8..15} a_H²     +  Σ_{8..15}(a_L−8)²
β  = 2⁴·Σ_{0..7} b²       +  Σ_{0..7}(b−8)²        +  2⁴·Σ_{8..15} b²       +  Σ_{8..15}(b−8)²
C  = 0 + 512 + 0 + 512 = 1024
```

- `α = PE(A,0)` (zero b): the `a_H` block gives `a_H²`, the `a_L` block gives `(a_L−8)²`.
- `β = PE(0,B)` (zero a): `a_H = 0` → `b²`; `a_L = 0` is **unsigned**, so it centers to −8 → `(b−8)²`. This is why the same `b` appears as both `b²` and `(b−8)²`, even though `b` is signed — the −8 is `a_L`'s biased zero, not a bias on `b`.
- `C`: each `a_L·b` block contributes `8 lanes × S² = 8 × 64 = 512`; two such blocks → **1024**.

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β.
- Centering: flip the MSB of each **unsigned** nibble (`a_L`). `b` is signed → no flip. This −8 is shared by the PE and the generators (dispatcher output).
- `β`'s extra `−8` (giving `b−8`) is the removed `a_L`'s bias, applied **only** in the β generator as a 2-gate top-bit remap (set bit 4, flip bit 3). See [square_basics.tex](./square_basics.tex).
- `C = 1024` is a per-mode constant, injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

`a = 0xFF = −1` (`a_H = −1`, `a_L = 15`), `b = 7`  →  `a·b = −7`:

```
a_H·b : ½(36 − 1 − 49 + 0)   = −7 ,  ×2⁴ = −112     [(−1+7)²=36, (−1)²=1, 7²=49]
a_L·b : ½(196 − 49 − 1 + 64) = 105,  ×1  = +105     [(7+7)²=196, 7²=49, (−1)²=1, C=64]
                                        total = −7 = (−1)·7  ✓
```
