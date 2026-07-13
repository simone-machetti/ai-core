# Mode 9 — Square (centered / opt)

Companion notes to [mode_9_opt.tex](./mode_9_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_9.tex](./mode_9.tex).

Mode 9 is a real **int16 × int16** dot product over 8 lanes (1 group):

```
DP8(16×16) = Σ_{i=0..7} a_i · b_i      a = int16,  b = int16
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP8(16×16) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

Both operands are int16, split into **four** nibbles each. Per the signedness rule, **only the single most-significant nibble is signed**; every lower nibble is unsigned:

- `a` (int16) = `2¹²·a_H^hi + 2⁸·a_L^hi + 2⁴·a_H^lo + a_L^lo` — `a_H^hi` **signed**; `a_L^hi`, `a_H^lo`, `a_L^lo` **unsigned**.
- `b` (int16) = `2¹²·b^hh + 2⁸·b^hl + 2⁴·b^lh + b^ll` — `b^hh` **signed**; `b^hl`, `b^lh`, `b^ll` **unsigned**.

Each lane is `a·b = Σ (2^p·a-nibble)(2^q·b-nibble)`, i.e. **16 nibble products** = **16 DP8(4×4) blocks** (one group of 8 lanes, so each block is summed over `i = 0..7` and appears once). No negation: every block is added.

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. The weights come from the positional product of the two nibble weights (`2^p · 2^q`). Blocks in dispatch order:

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C/lane |
|---|---|---|---|---|---|---|---|
| `a_H^hi·b^hh` | 2²⁴ | 0 0 | (1) both signed | `(a_H^hi + b^hh)²` | `(a_H^hi)²` | `(b^hh)²` | 0 |
| `a_L^hi·b^hh` | 2²⁰ | 1 0 | (3) A unsigned | `((a_L^hi−8) + b^hh)²` | `(a_L^hi−8)²` | `(b^hh−8)²` | 64 |
| `a_H^hi·b^hl` | 2²⁰ | 0 1 | (3) B unsigned | `(a_H^hi + (b^hl−8))²` | `(a_H^hi−8)²` | `(b^hl−8)²` | 64 |
| `a_L^hi·b^hl` | 2¹⁶ | 1 1 | (5) both unsigned | `((a_L^hi−8) + (b^hl−8))²` | `(a_L^hi−16)²` | `(b^hl−16)²` | 256 |
| `a_H^lo·b^hh` | 2¹⁶ | 1 0 | (3) A unsigned | `((a_H^lo−8) + b^hh)²` | `(a_H^lo−8)²` | `(b^hh−8)²` | 64 |
| `a_L^lo·b^hh` | 2¹² | 1 0 | (3) A unsigned | `((a_L^lo−8) + b^hh)²` | `(a_L^lo−8)²` | `(b^hh−8)²` | 64 |
| `a_H^hi·b^lh` | 2¹⁶ | 0 1 | (3) B unsigned | `(a_H^hi + (b^lh−8))²` | `(a_H^hi−8)²` | `(b^lh−8)²` | 64 |
| `a_L^hi·b^lh` | 2¹² | 1 1 | (5) both unsigned | `((a_L^hi−8) + (b^lh−8))²` | `(a_L^hi−16)²` | `(b^lh−16)²` | 256 |
| `a_H^lo·b^hl` | 2¹² | 1 1 | (5) both unsigned | `((a_H^lo−8) + (b^hl−8))²` | `(a_H^lo−16)²` | `(b^hl−16)²` | 256 |
| `a_L^lo·b^hl` | 2⁸ | 1 1 | (5) both unsigned | `((a_L^lo−8) + (b^hl−8))²` | `(a_L^lo−16)²` | `(b^hl−16)²` | 256 |
| `a_H^hi·b^ll` | 2¹² | 0 1 | (3) B unsigned | `(a_H^hi + (b^ll−8))²` | `(a_H^hi−8)²` | `(b^ll−8)²` | 64 |
| `a_L^hi·b^ll` | 2⁸ | 1 1 | (5) both unsigned | `((a_L^hi−8) + (b^ll−8))²` | `(a_L^hi−16)²` | `(b^ll−16)²` | 256 |
| `a_H^lo·b^lh` | 2⁸ | 1 1 | (5) both unsigned | `((a_H^lo−8) + (b^lh−8))²` | `(a_H^lo−16)²` | `(b^lh−16)²` | 256 |
| `a_L^lo·b^lh` | 2⁴ | 1 1 | (5) both unsigned | `((a_L^lo−8) + (b^lh−8))²` | `(a_L^lo−16)²` | `(b^lh−16)²` | 256 |
| `a_H^lo·b^ll` | 2⁴ | 1 1 | (5) both unsigned | `((a_H^lo−8) + (b^ll−8))²` | `(a_H^lo−16)²` | `(b^ll−16)²` | 256 |
| `a_L^lo·b^ll` | 2⁰ | 1 1 | (5) both unsigned | `((a_L^lo−8) + (b^ll−8))²` | `(a_L^lo−16)²` | `(b^ll−16)²` | 256 |

Only the top-nibble pair `a_H^hi·b^hh` hits case (1) (both signed, `C=0`); every block that pairs a signed top nibble with a lower nibble is case (3) (`C/lane=64`); the 10 lower×lower blocks are case (5) (`C/lane=256`).

## Components

`PE`, `α`, `β` are the weighted sums over all 16 blocks; each per-block term is taken from the table above, summed over that block's 8 lanes:

```
PE = Σ_blocks  weight · Σ_lanes (PE arg)
α  = Σ_blocks  weight · Σ_lanes (α term)
β  = Σ_blocks  weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

The same nibble is squared several ways because its partner (hence `S`) varies:

- `α`: `a_H^hi` appears as `(a_H^hi)²` (paired with signed `b^hh`, S=0) **and** `(a_H^hi−8)²` (paired with any unsigned `b`, S=8); each unsigned a-nibble appears as `(·−8)²` (partner signed, S=8) and `(·−16)²` (partner unsigned, S=16).
- `β`: symmetric — `b^hh` gives `(b^hh)²` and `(b^hh−8)²`; each unsigned b-nibble gives `(·−8)²` and `(·−16)²`.

The extra `−8` on a signed nibble (e.g. `a_H^hi−8`, `b^hh−8`) is the **removed operand's biased zero** — see [square_basics.tex](./square_basics.tex) for the `α = PE(A,0)` / `β = PE(0,B)` derivation.

## Constant C

Each block contributes `weight × (8 lanes × S²)`, with `8·S² = 0 / 512 / 2048` for `S = 0 / 8 / 16`:

| block | weight | 8·S² | contribution |
|---|---|---|---|
| `a_H^hi·b^hh` | 2²⁴ | 0 | 0 |
| `a_L^hi·b^hh` | 2²⁰ | 512 | 536870912 |
| `a_H^hi·b^hl` | 2²⁰ | 512 | 536870912 |
| `a_L^hi·b^hl` | 2¹⁶ | 2048 | 134217728 |
| `a_H^lo·b^hh` | 2¹⁶ | 512 | 33554432 |
| `a_L^lo·b^hh` | 2¹² | 512 | 2097152 |
| `a_H^hi·b^lh` | 2¹⁶ | 512 | 33554432 |
| `a_L^hi·b^lh` | 2¹² | 2048 | 8388608 |
| `a_H^lo·b^hl` | 2¹² | 2048 | 8388608 |
| `a_L^lo·b^hl` | 2⁸ | 2048 | 524288 |
| `a_H^hi·b^ll` | 2¹² | 512 | 2097152 |
| `a_L^hi·b^ll` | 2⁸ | 2048 | 524288 |
| `a_H^lo·b^lh` | 2⁸ | 2048 | 524288 |
| `a_L^lo·b^lh` | 2⁴ | 2048 | 32768 |
| `a_H^lo·b^ll` | 2⁴ | 2048 | 32768 |
| `a_L^lo·b^ll` | 2⁰ | 2048 | 2048 |

```
C = 0 + 536870912 + 536870912 + 134217728 + 33554432 + 2097152 + 33554432 + 8388608
  + 8388608 + 524288 + 2097152 + 524288 + 524288 + 32768 + 32768 + 2048 = 1297680384
```

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β (unchanged from modes 1/2 — only the operands, weights, and `C` differ).
- Centering: at the dispatcher, flip the MSB of each **unsigned** nibble (`a_L^hi`, `a_H^lo`, `a_L^lo`, `b^hl`, `b^lh`, `b^ll`); the two signed top nibbles (`a_H^hi`, `b^hh`) are not flipped. This −8 is shared by the PE and the α/β generators.
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): this turns a signed top nibble into `·−8` when its partner is unsigned (S=8 blocks), and an already-centered unsigned nibble into `·−16` (S=16 blocks).
- `C = 1297680384` is a per-mode constant, injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

`a = b = 0xFFFF = −1` on every lane (`a_H^hi = b^hh = −1`; `a_L^hi = a_H^lo = a_L^lo = b^hl = b^lh = b^ll = 15`) → per lane `a·b = 1`. Per-lane reconstruction (`C/lane = S²`), block by block:

```
a_H^hi·b^hh (00): ½(  4 −  1 −  1 +   0) =  1 , ×2²⁴ = +16777216
a_L^hi·b^hh (10): ½( 36 − 49 − 81 +  64) = −15, ×2²⁰ = −15728640
a_H^hi·b^hl (01): ½( 36 − 81 − 49 +  64) = −15, ×2²⁰ = −15728640
a_L^hi·b^hl (11): ½(196 −  1 −  1 + 256) = 225, ×2¹⁶ = +14745600
a_H^lo·b^hh (10): ½( 36 − 49 − 81 +  64) = −15, ×2¹⁶ =   −983040
a_L^lo·b^hh (10): ½( 36 − 49 − 81 +  64) = −15, ×2¹² =    −61440
a_H^hi·b^lh (01): ½( 36 − 81 − 49 +  64) = −15, ×2¹⁶ =   −983040
a_L^hi·b^lh (11): ½(196 −  1 −  1 + 256) = 225, ×2¹² =   +921600
a_H^lo·b^hl (11): ½(196 −  1 −  1 + 256) = 225, ×2¹² =   +921600
a_L^lo·b^hl (11): ½(196 −  1 −  1 + 256) = 225, ×2⁸  =    +57600
a_H^hi·b^ll (01): ½( 36 − 81 − 49 +  64) = −15, ×2¹² =    −61440
a_L^hi·b^ll (11): ½(196 −  1 −  1 + 256) = 225, ×2⁸  =    +57600
a_H^lo·b^lh (11): ½(196 −  1 −  1 + 256) = 225, ×2⁸  =    +57600
a_L^lo·b^lh (11): ½(196 −  1 −  1 + 256) = 225, ×2⁴  =     +3600
a_H^lo·b^ll (11): ½(196 −  1 −  1 + 256) = 225, ×2⁴  =     +3600
a_L^lo·b^ll (11): ½(196 −  1 −  1 + 256) = 225, ×2⁰  =       +225
                                                    total =  1 = (−1)·(−1)  ✓
```

(Over all 8 identical lanes the group result is `8·1 = 8`; the per-mode block constant `8·S²` folds the 8 lanes into the single accumulator constant `C = 1297680384`.)
