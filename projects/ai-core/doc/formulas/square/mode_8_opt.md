# Mode 8 — Square (centered / opt)

Companion notes to [mode_8_opt.tex](./mode_8_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_8.tex](./mode_8.tex).

Mode 8 is a real **int16 × int16** dot product — the largest real mode:

```
DP16(16×16) = Σ_{i=0..15} a_i · b_i      a = int16,  b = int16
```

The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`:

```
Result = DP16(16×16) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

Each int16 operand splits into **four** nibbles. Only the single **most-significant** nibble of each operand is **signed**; the other three are **unsigned**:

- `a` (int16) = `2¹²·a_H^hi + 2⁸·a_L^hi + 2⁴·a_H^lo + a_L^lo` — `a_H^hi` **signed**, `a_L^hi`, `a_H^lo`, `a_L^lo` **unsigned**.
- `b` (int16) = `2¹²·b^hh + 2⁸·b^hl + 2⁴·b^lh + b^ll` — `b^hh` **signed**, `b^hl`, `b^lh`, `b^ll` **unsigned**.

Each lane is therefore **4 × 4 = 16** nibble products. The 16-lane dot product is done as **two half-groups** (i = 0..7, 8..15), giving **32 DP8(4×4) blocks** (16 distinct block types × 2 halves).

A block's weight is `2^(ea+eb)`, where `ea`/`eb` are the two nibbles' position exponents (`a_H^hi,b^hh = 2¹²`; `a_L^hi,b^hl = 2⁸`; `a_H^lo,b^lh = 2⁴`; `a_L^lo,b^ll = 2⁰`).

## Per-block table

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. Each of the 16 rows is summed over its 8 lanes and appears once per half (×2). Only `a_H^hi·b^hh` is both-signed (`S=0`); six blocks are one-unsigned (`S=8`); nine are both-unsigned (`S=16`).

| block | weight | au bu | f | PE arg | α = (A−S)² | β = (B−S)² | C/lane |
|---|---|---|---|---|---|---|---|
| `a_H^hi·b^hh` | 2²⁴ | 0 0 | (1) | `(a_H^hi + b^hh)²` | `(a_H^hi)²` | `(b^hh)²` | 0 |
| `a_L^hi·b^hh` | 2²⁰ | 1 0 | (3) | `((a_L^hi−8) + b^hh)²` | `(a_L^hi−8)²` | `(b^hh−8)²` | 64 |
| `a_H^hi·b^hl` | 2²⁰ | 0 1 | (3) | `(a_H^hi + (b^hl−8))²` | `(a_H^hi−8)²` | `(b^hl−8)²` | 64 |
| `a_L^hi·b^hl` | 2¹⁶ | 1 1 | (5) | `((a_L^hi−8) + (b^hl−8))²` | `(a_L^hi−16)²` | `(b^hl−16)²` | 256 |
| `a_H^lo·b^hh` | 2¹⁶ | 1 0 | (3) | `((a_H^lo−8) + b^hh)²` | `(a_H^lo−8)²` | `(b^hh−8)²` | 64 |
| `a_L^lo·b^hh` | 2¹² | 1 0 | (3) | `((a_L^lo−8) + b^hh)²` | `(a_L^lo−8)²` | `(b^hh−8)²` | 64 |
| `a_H^hi·b^lh` | 2¹⁶ | 0 1 | (3) | `(a_H^hi + (b^lh−8))²` | `(a_H^hi−8)²` | `(b^lh−8)²` | 64 |
| `a_L^hi·b^lh` | 2¹² | 1 1 | (5) | `((a_L^hi−8) + (b^lh−8))²` | `(a_L^hi−16)²` | `(b^lh−16)²` | 256 |
| `a_H^lo·b^hl` | 2¹² | 1 1 | (5) | `((a_H^lo−8) + (b^hl−8))²` | `(a_H^lo−16)²` | `(b^hl−16)²` | 256 |
| `a_L^lo·b^hl` | 2⁸ | 1 1 | (5) | `((a_L^lo−8) + (b^hl−8))²` | `(a_L^lo−16)²` | `(b^hl−16)²` | 256 |
| `a_H^hi·b^ll` | 2¹² | 0 1 | (3) | `(a_H^hi + (b^ll−8))²` | `(a_H^hi−8)²` | `(b^ll−8)²` | 64 |
| `a_L^hi·b^ll` | 2⁸ | 1 1 | (5) | `((a_L^hi−8) + (b^ll−8))²` | `(a_L^hi−16)²` | `(b^ll−16)²` | 256 |
| `a_H^lo·b^lh` | 2⁸ | 1 1 | (5) | `((a_H^lo−8) + (b^lh−8))²` | `(a_H^lo−16)²` | `(b^lh−16)²` | 256 |
| `a_L^lo·b^lh` | 2⁴ | 1 1 | (5) | `((a_L^lo−8) + (b^lh−8))²` | `(a_L^lo−16)²` | `(b^lh−16)²` | 256 |
| `a_H^lo·b^ll` | 2⁴ | 1 1 | (5) | `((a_H^lo−8) + (b^ll−8))²` | `(a_H^lo−16)²` | `(b^ll−16)²` | 256 |
| `a_L^lo·b^ll` | 2⁰ | 1 1 | (5) | `((a_L^lo−8) + (b^ll−8))²` | `(a_L^lo−16)²` | `(b^ll−16)²` | 256 |

Weights come from `a·b = (Σ_p 2^{ep} a_p)(Σ_q 2^{eq} b_q) = Σ_{p,q} 2^{ep+eq} a_p b_q` — the 16 nibble cross-products. The block order above matches the box in the `.tex` (row `r` = blocks `2r`, `2r+1`, each shown for both halves).

## Components

`PE`, `α`, `β` are the weighted sums over all **32 blocks** (16 types × 2 halves); each per-block term is taken from the table above, summed over that block's 8 lanes:

```
PE = Σ_blocks  weight · Σ_lanes (PE arg)
α  = Σ_blocks  weight · Σ_lanes (α term)
β  = Σ_blocks  weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

`α = PE(A,0)` (zero b) and `β = PE(0,B)` (zero a). The same nibble appears squared several ways because its partner (and hence `S`) varies — e.g. `a_H^hi` is signed but still shows as `(a_H^hi)²` (paired with signed `b^hh`, S=0) **and** `(a_H^hi−8)²` (paired with an unsigned `b`, S=8); each unsigned `a` nibble shows as `(A−8)²` (S=8) and `(A−16)²` (S=16). The extra `−8`/`−16` on a nibble is the **removed operand's biased zero**, not a bias on that nibble itself — see [square_basics.tex](./square_basics.tex) for the `α = PE(A,0)` / `β = PE(0,B)` derivation.

## Constant C

Each block contributes `weight × (8 lanes × S²)`:

| block | weight | 8·S² | contribution |
|---|---|---|---|
| `a_H^hi·b^hh` | 2²⁴ | 0 | 0 |
| `a_L^hi·b^hh` | 2²⁰ | 512 | 2²⁹ = 536870912 |
| `a_H^hi·b^hl` | 2²⁰ | 512 | 2²⁹ = 536870912 |
| `a_L^hi·b^hl` | 2¹⁶ | 2048 | 2²⁷ = 134217728 |
| `a_H^lo·b^hh` | 2¹⁶ | 512 | 2²⁵ = 33554432 |
| `a_L^lo·b^hh` | 2¹² | 512 | 2²¹ = 2097152 |
| `a_H^hi·b^lh` | 2¹⁶ | 512 | 2²⁵ = 33554432 |
| `a_L^hi·b^lh` | 2¹² | 2048 | 2²³ = 8388608 |
| `a_H^lo·b^hl` | 2¹² | 2048 | 2²³ = 8388608 |
| `a_L^lo·b^hl` | 2⁸ | 2048 | 2¹⁹ = 524288 |
| `a_H^hi·b^ll` | 2¹² | 512 | 2²¹ = 2097152 |
| `a_L^hi·b^ll` | 2⁸ | 2048 | 2¹⁹ = 524288 |
| `a_H^lo·b^lh` | 2⁸ | 2048 | 2¹⁹ = 524288 |
| `a_L^lo·b^lh` | 2⁴ | 2048 | 2¹⁵ = 32768 |
| `a_H^lo·b^ll` | 2⁴ | 2048 | 2¹⁵ = 32768 |
| `a_L^lo·b^ll` | 2⁰ | 2048 | 2¹¹ = 2048 |

Per half-group the 16 contributions sum to **1297680384**; over both halves:

```
C = 2 · 1297680384 = 2595360768
```

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β (identical primitive to modes 1/2 — only the operands, weights, and `C` differ). See [square_basics.tex](./square_basics.tex).
- **Centering (dispatcher):** flip the MSB of each **unsigned** nibble (`a_L^hi`, `a_H^lo`, `a_L^lo`, `b^hl`, `b^lh`, `b^ll`); the two signed MSNs (`a_H^hi`, `b^hh`) are not flipped. This `−8` is shared by the PE and the α/β generators.
- **Generator −8 bit:** each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): S=8 blocks give `A−8`/`B−8`, S=16 blocks give `A−16`/`B−16`.
- `C = 2595360768` is a **per-mode constant**, injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

Single lane `a = b = 0xFFFF = −1`. Nibbles: signed `a_H^hi = b^hh = −1`; unsigned `a_L^hi = a_H^lo = a_L^lo = b^hl = b^lh = b^ll = 15`. So `a = b = 2¹²·(−1) + 2⁸·15 + 2⁴·15 + 15 = −1`, and `a·b = 1`.

The four block **types** (per lane, `C = S²`):

```
both signed (S=0) : ½(4   − 1  − 1  + 0)   =   1   = (−1)·(−1)
A unsigned  (S=8) : ½(36  − 49 − 81 + 64)  = −15   =   15 ·(−1)   [(7−1)²=36, (15−8)²=49, (−1−8)²=81]
B unsigned  (S=8) : ½(36  − 81 − 49 + 64)  = −15   = (−1)· 15
both unsig. (S=16): ½(196 − 1  − 1  + 256) = 225   =   15 · 15    [(7+7)²=196, (15−16)²=1, C=256]
```

Weighting each of the 16 blocks by its `2^(ea+eb)` and summing (per lane):

```
 2²⁴·(1) + 2²⁰·(−15) + 2²⁰·(−15) + 2¹⁶·(225)     [a·b^hh row + a_{H,L}^hi·b^hl]
+2¹⁶·(−15) + 2¹²·(−15) + 2¹⁶·(−15) + 2¹²·(225)
+2¹²·(225) + 2⁸·(225)  + 2¹²·(−15) + 2⁸·(225)
+2⁸·(225)  + 2⁴·(225)  + 2⁴·(225)  + 2⁰·(225)
                                       = 1  = (−1)·(−1)   ✓
```

Over all 16 identical lanes → `DP = 16` (reconstructed by the box with `C = 2595360768`). The generator/verifier (`½(PE−α−β+C)` vs `Σ a_i·b_i`) matches on 40256 random + corner vectors, with every square argument in [−16,14].
