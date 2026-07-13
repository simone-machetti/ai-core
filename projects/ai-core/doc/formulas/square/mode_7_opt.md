# Mode 7 — Square (centered / opt)

Companion notes to [mode_7_opt.tex](./mode_7_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_7.tex](./mode_7.tex).

Mode 7 is a real **int16 × int8** dot product:

```
DP16(16×8) = Σ_{i=0..15} a_i · b_i      a = int16,  b = int8
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP16(16×8) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

The 16 lanes are processed as **2 groups of 8** (i = 0..7 and 8..15). Within a group each operand is split so that **only the single most-significant nibble is signed**; every lower nibble is **unsigned** (gets the −8 bias):

- `a` (int16) = `2¹²·a_H^hi + 2⁸·a_L^hi + 2⁴·a_H^lo + a_L^lo` — `a_H^hi` **signed**, `a_L^hi, a_H^lo, a_L^lo` **unsigned**.
- `b` (int8)  = `2⁴·b^hi + b^lo` — `b^hi` **signed**, `b^lo` **unsigned**.

(Superscript `hi/lo` = high/low byte; subscript `H/L` = high/low nibble within that byte.)

Each lane is therefore **4 a-nibbles × 2 b-nibbles = 8 nibble products**, i.e. **8 DP8(4×4) blocks per group**, **16 blocks total**.

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. Each block is summed over its 8 lanes and appears once per group.

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C / lane |
|---|---|---|---|---|---|---|---|
| `a_H^hi·b^hi` | 2¹⁶ | 0 0 | (1) both signed | `(a_H^hi + b^hi)²` | `(a_H^hi)²` | `(b^hi)²` | 0 |
| `a_L^hi·b^hi` | 2¹² | 1 0 | (3) A unsigned | `((a_L^hi−8) + b^hi)²` | `(a_L^hi−8)²` | `(b^hi−8)²` | 64 |
| `a_H^hi·b^lo` | 2¹² | 0 1 | (3) B unsigned | `(a_H^hi + (b^lo−8))²` | `(a_H^hi−8)²` | `(b^lo−8)²` | 64 |
| `a_L^hi·b^lo` | 2⁸ | 1 1 | (5) both unsigned | `((a_L^hi−8) + (b^lo−8))²` | `(a_L^hi−16)²` | `(b^lo−16)²` | 256 |
| `a_H^lo·b^hi` | 2⁸ | 1 0 | (3) A unsigned | `((a_H^lo−8) + b^hi)²` | `(a_H^lo−8)²` | `(b^hi−8)²` | 64 |
| `a_L^lo·b^hi` | 2⁴ | 1 0 | (3) A unsigned | `((a_L^lo−8) + b^hi)²` | `(a_L^lo−8)²` | `(b^hi−8)²` | 64 |
| `a_H^lo·b^lo` | 2⁴ | 1 1 | (5) both unsigned | `((a_H^lo−8) + (b^lo−8))²` | `(a_H^lo−16)²` | `(b^lo−16)²` | 256 |
| `a_L^lo·b^lo` | 2⁰ | 1 1 | (5) both unsigned | `((a_L^lo−8) + (b^lo−8))²` | `(a_L^lo−16)²` | `(b^lo−16)²` | 256 |

Weights come from `a·b = (2¹²a_H^hi + 2⁸a_L^hi + 2⁴a_H^lo + a_L^lo)(2⁴b^hi + b^lo)`: each a-nibble weight (2¹²,2⁸,2⁴,2⁰) times each b-nibble weight (2⁴,2⁰) gives 2¹⁶,2¹²,2¹²,2⁸,2⁸,2⁴,2⁴,2⁰. Only `a_H^hi·b^hi` (both top nibbles) is fully signed; every other block has at least one unsigned nibble.

## Components

`PE`, `α`, `β` are the weighted sums over all 16 blocks (8 types × 2 groups); each per-block term is taken from the table above, summed over that block's lanes:

```
PE = Σ_blocks  weight · Σ_lanes (PE arg)
α  = Σ_blocks  weight · Σ_lanes (α term)
β  = Σ_blocks  weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

The same nibble appears squared several ways because its partner (and hence `S`) varies:

- `α`: a signed `a_H^hi` gives `(a_H^hi)²` (paired with signed `b^hi`, S=0) **and** `(a_H^hi−8)²` (paired with unsigned `b^lo`, S=8); an unsigned a-nibble like `a_L^hi` gives `(a_L^hi−8)²` (S=8) and `(a_L^hi−16)²` (S=16).
- `β`: `b^hi` gives `(b^hi)²` (S=0) and `(b^hi−8)²` (S=8); `b^lo` gives `(b^lo−8)²` (S=8) and `(b^lo−16)²` (S=16).

The extra `−8` on a *signed* nibble (e.g. `a_H^hi−8`, `b^hi−8`) is the **removed operand's biased zero** — see [square_basics.tex](./square_basics.tex) for the `α = PE(A,0)` / `β = PE(0,B)` derivation.

## Constant C

Each block contributes `weight × (8 lanes × S²)` per group:

| block | weight | 8·S² | contribution / group |
|---|---|---|---|
| `a_H^hi·b^hi` | 2¹⁶ | 0 | 0 |
| `a_L^hi·b^hi` | 2¹² | 512 | 2097152 |
| `a_H^hi·b^lo` | 2¹² | 512 | 2097152 |
| `a_L^hi·b^lo` | 2⁸ | 2048 | 524288 |
| `a_H^lo·b^hi` | 2⁸ | 512 | 131072 |
| `a_L^lo·b^hi` | 2⁴ | 512 | 8192 |
| `a_H^lo·b^lo` | 2⁴ | 2048 | 32768 |
| `a_L^lo·b^lo` | 2⁰ | 2048 | 2048 |

Per group = `0 + 2097152 + 2097152 + 524288 + 131072 + 8192 + 32768 + 2048 = 4892672`. Over both groups:

```
C = 2 × 4892672 = 9785344
```

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β (unchanged from modes 1–2 — only the operands, weights, and `C` differ).
- Centering: flip the MSB of each **unsigned** nibble (`a_L^hi`, `a_H^lo`, `a_L^lo`, `b^lo`); the signed nibbles (`a_H^hi`, `b^hi`) are not flipped. Shared by PE and generators (dispatcher output).
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): this turns a signed nibble `X → X−8` in S=8 blocks and an unsigned nibble `X−8 → X−16` in S=16 blocks.
- `C = 9785344` is a per-mode constant, injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

`a = 0xFFFF = −1` (`a_H^hi = −1`, `a_L^hi = a_H^lo = a_L^lo = 15`), `b = 0xFF = −1` (`b^hi = −1`, `b^lo = 15`)  →  per lane `a·b = 1`:

```
a_H^hi·b^hi (2¹⁶): ½( (−2)² − (−1)² − (−1)² + 0 )    =   1 , ×2¹⁶ = +65536
a_L^hi·b^hi (2¹²): ½( 6²  − 7²   − (−9)² + 64 )      = −15 , ×2¹² = −61440
a_H^hi·b^lo (2¹²): ½( 6²  − (−9)²− 7²    + 64 )      = −15 , ×2¹² = −61440
a_L^hi·b^lo (2⁸ ): ½( 14² − (−1)²− (−1)² + 256 )     = 225 , ×2⁸  = +57600
a_H^lo·b^hi (2⁸ ): ½( 6²  − 7²   − (−9)² + 64 )      = −15 , ×2⁸  =  −3840
a_L^lo·b^hi (2⁴ ): ½( 6²  − 7²   − (−9)² + 64 )      = −15 , ×2⁴  =   −240
a_H^lo·b^lo (2⁴ ): ½( 14² − (−1)²− (−1)² + 256 )     = 225 , ×2⁴  =  +3600
a_L^lo·b^lo (2⁰ ): ½( 14² − (−1)²− (−1)² + 256 )     = 225 , ×1   =   +225
                                                       lane total = 1 = (−1)·(−1)  ✓
```

All 16 lanes give 1 → `Result = 16`. A full random + corner sweep (int16 × int8, 40000 vectors incl. 0, ±1, 0x7F, −0x80, 0x7FFF, −0x8000) confirms `½(PE−α−β+C) = Σ aᵢ·bᵢ` with every square argument in [−16,14].
