# Mode 3 — Square (centered / opt)

Companion notes to [mode_3_opt.tex](./mode_3_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_3.tex](./mode_3.tex).

Mode 3 is a real **int16 × int8** dot product:

```
DP8(16×8) = Σ_{i=0..7} a_i · b_i      a = int16,  b = int8,  8 lanes
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP8(16×8) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

Only the single most-significant nibble of each independent operand is **signed**; every lower nibble is **unsigned** (gets the −8 bias).

- `a` (int16) = `2¹²·a_H^hi + 2⁸·a_L^hi + 2⁴·a_H^lo + a_L^lo` — `a_H^hi` signed; `a_L^hi`, `a_H^lo`, `a_L^lo` **unsigned**.
- `b` (int8) = `2⁴·b^hi + b^lo` — `b^hi` signed; `b^lo` **unsigned**.

So each lane becomes the 4×2 = **8 nibble products** below (one DP8(4×4) block each, all 8 lanes summed). Weights come from expanding `a·b`; e.g. `a_H^hi·b^hi` has weight `2¹²·2⁴ = 2¹⁶`.

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. Each block is summed over its 8 lanes (i = 0..7).

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

Mode 3 exercises all three signedness cases: `a_H^hi·b^hi` is the only both-signed block; three blocks are both-unsigned; the remaining four have exactly one unsigned nibble.

## Components

`PE`, `α`, `β` are the weighted sums over all 8 blocks; each per-block term is taken from the table above, summed over that block's 8 lanes:

```
PE = Σ_blocks  weight · Σ_lanes (PE arg)
α  = Σ_blocks  weight · Σ_lanes (α term)
β  = Σ_blocks  weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

The same nibble appears squared several ways because its partner varies:

- `α`: `a_H^hi` gives `(a_H^hi)²` (with `b^hi`, S=0) **and** `(a_H^hi−8)²` (with `b^lo`, S=8); each unsigned a-nibble gives a `−8` form (paired with signed `b^hi`) and a `−16` form (paired with unsigned `b^lo`).
- `β`: `b^hi` gives `(b^hi)²` (with signed `a_H^hi`) and `(b^hi−8)²` (with any unsigned a-nibble); `b^lo` gives `(b^lo−8)²` and `(b^lo−16)²`.

The extra `−8` on a signed nibble (e.g. `a_H^hi−8`, `b^hi−8`) is the **removed operand's biased zero** — see [square_basics.tex](./square_basics.tex) for the `α = PE(A,0)` / `β = PE(0,B)` derivation.

## Constant C

Each block contributes `weight × (8 lanes × S²)`:

| block | weight | 8·S² | contribution |
|---|---|---|---|
| `a_H^hi·b^hi` | 2¹⁶ | 0 | 0 |
| `a_L^hi·b^hi` | 2¹² | 512 | 2 097 152 |
| `a_H^hi·b^lo` | 2¹² | 512 | 2 097 152 |
| `a_L^hi·b^lo` | 2⁸ | 2048 | 524 288 |
| `a_H^lo·b^hi` | 2⁸ | 512 | 131 072 |
| `a_L^lo·b^hi` | 2⁴ | 512 | 8 192 |
| `a_H^lo·b^lo` | 2⁴ | 2048 | 32 768 |
| `a_L^lo·b^lo` | 2⁰ | 2048 | 2 048 |

```
C = 0 + 2097152 + 2097152 + 524288 + 131072 + 8192 + 32768 + 2048 = 4892672
```

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β (unchanged from modes 1–2 — only the operands, weights, and `C` differ).
- Centering: flip the MSB of each **unsigned** nibble (`a_L^hi`, `a_H^lo`, `a_L^lo`, `b^lo`); the signed nibbles (`a_H^hi`, `b^hi`) are not flipped. Shared by PE and the α/β generators (dispatcher output).
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): this turns signed nibbles into their `−8` form (S=8 blocks) and unsigned nibbles into their `−16` form (S=16 blocks).
- `C = 4 892 672` is a per-mode constant, injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

`a = 0xFFFF = −1` (`a_H^hi = −1`, `a_L^hi = a_H^lo = a_L^lo = 15`), `b = 0xFF = −1` (`b^hi = −1`, `b^lo = 15`) → per-lane `a·b = 1`:

```
a_H^hi·b^hi (00): ½( 4  −  1 −  1 +   0) =   1 , ×2¹⁶ = +65536
a_L^hi·b^hi (10): ½(36  − 49 − 81 +  64) = −15 , ×2¹² = −61440
a_H^hi·b^lo (01): ½(36  − 81 − 49 +  64) = −15 , ×2¹² = −61440
a_L^hi·b^lo (11): ½(196 −  1 −  1 + 256) = 225 , ×2⁸  = +57600
a_H^lo·b^hi (10): ½(36  − 49 − 81 +  64) = −15 , ×2⁸  =  −3840
a_L^lo·b^hi (10): ½(36  − 49 − 81 +  64) = −15 , ×2⁴  =   −240
a_H^lo·b^lo (11): ½(196 −  1 −  1 + 256) = 225 , ×2⁴  =  +3600
a_L^lo·b^lo (11): ½(196 −  1 −  1 + 256) = 225 , ×2⁰  =   +225
                                                total =   1 = (−1)·(−1)  ✓
```

Over 8 identical lanes the dot product is `8 · 1 = 8`. A randomized + corner sweep (int16 × int8 vectors, plus `0, −1, 0x7F, −0x80, 0xFF`, type min/max) confirms the reconstruction equals `Σ a_i·b_i` and every square argument stays in [−16,14].
