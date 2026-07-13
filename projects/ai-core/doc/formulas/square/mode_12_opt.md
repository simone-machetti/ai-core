# Mode 12 — Square (centered / opt)

Companion notes to [mode_12_opt.tex](./mode_12_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_12.tex](./mode_12.tex).

Mode 12 is a **complex** dot product `C-DP4(C16×C16)` over **4 complex lanes**, each part **int16**:

```
D = Σ_{i=0..3} a_i · b_i      a_i = a^re_i + j·a^im_i ,  b_i = b^re_i + j·b^im_i
Re(D) = Σ a^re·b^re − Σ a^im·b^im        (the a^im·b^im group is NEGATED)
Im(D) = Σ a^re·b^im + Σ a^im·b^re        (all +)
```

Each of `Re(D)` and `Im(D)` is a real DP over nibble products, evaluated with the **add-then-square** trick on centered ≤5-bit operands, compensated by an A-only term `α`, a B-only term `β`, and a constant `C`. There is a **separate box for each**:

```
Re(D) = ½ · (PE − α − β + C)          Im(D) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square argument is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

`a^re, a^im, b^re, b^im` are **four independent int16 operands**. Each int16 `X` splits into four nibbles (only its single most-significant nibble is signed):

```
X = 2¹²·X_H^hi + 2⁸·X_L^hi + 2⁴·X_H^lo + 2⁰·X_L^lo
      signed      unsigned     unsigned     unsigned
```

- `a`-side: byte-split `a = 2⁸·a^hi + a^lo`, then nibble each byte → `a_H^hi` (signed), `a_L^hi`, `a_H^lo`, `a_L^lo` (unsigned). Weights `2¹²,2⁸,2⁴,2⁰`.
- `b`-side: nibbles `b^hh` (signed), `b^hl`, `b^lh`, `b^ll` (unsigned). Weights `2¹²,2⁸,2⁴,2⁰`.

A per-part product `X·Y` is the **outer product** of the 4 a-nibbles × 4 b-nibbles = **16 nibble blocks** (weight = weight(a-nibble)·weight(b-nibble), a DP8(4×4) over the 4 lanes each). So:

- **`Re(D)` box**: 16 blocks for `+ a^re·b^re` **and** 16 for `− a^im·b^im` → **32 blocks**.
- **`Im(D)` box**: 16 for `+ a^re·b^im` **and** 16 for `+ a^im·b^re` → **32 blocks**, all `+`.

## Negation of the `a^im·b^im` group (complex-specific)

The baseline square sheet writes each `−a^im·b^im` block as a **subtract-square** `(a^im − b^im)²` with positive α/β. That does **not** survive centering (the linear cross terms no longer cancel). Instead, in the opt form a negated block **keeps the add-square** `((a^im−δ)+(b^im−δ))²` but the **whole block carries a minus** — so `PE`, `α`, `β` **and** `C` for those 16 blocks all appear with a leading `−`, identically. `Im(D)` has no negated group (all `+`).

## Per-block table (by nibble type)

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`; each block is summed over its **4 lanes** so per block `C = 4·S²`. The a-side signed nibble is `a_H^hi`; the b-side signed nibble is `b^hh`; every other nibble is unsigned.

| nibble type | au bu | S | PE arg | α = (A−S)² | β = (B−S)² | C / lane | C / block (4 lanes) |
|---|---|---|---|---|---|---|---|
| signed · signed | 0 0 | 0 | `(A + B)²` | `A²` | `B²` | 0 | 0 |
| unsigned · signed | 1 0 | 8 | `((A−8) + B)²` | `(A−8)²` | `(B−8)²` | 64 | 256 |
| signed · unsigned | 0 1 | 8 | `(A + (B−8))²` | `(A−8)²` | `(B−8)²` | 64 | 256 |
| unsigned · unsigned | 1 1 | 16 | `((A−8) + (B−8))²` | `(A−16)²` | `(B−16)²` | 256 | 1024 |

Only `a_H^hi · b^hh` hits the `S=0` row; blocks mixing that signed nibble with an unsigned partner are `S=8`; all-lower nibble pairs are `S=16`.

## Components (aggregation rule)

`PE`, `α`, `β` are the signed weighted sums over all 32 blocks (block sign `s = +1` for `re·re`/`re·im`/`im·re`, `s = −1` for `im·im`):

```
PE = Σ_blocks  s · weight · Σ_lanes (PE arg)²
α  = Σ_blocks  s · weight · Σ_lanes (α  term)     (A-side only)
β  = Σ_blocks  s · weight · Σ_lanes (β  term)     (B-side only)
Result = ½ · (PE − α − β + C)
```

The same nibble reappears squared several ways because its partner (and hence `S`) varies, e.g. `a_H^hi` gives `(a_H^hi)²` when paired with the signed `b^hh` (S=0) and `(a_H^hi−8)²` when paired with any unsigned `b` nibble (S=8). The extra `−8`/`−16` on the removed operand is its biased zero — see [square_basics.tex](./square_basics.tex) for the `α = PE(A,0)` / `β = PE(0,B)` derivation.

## Constant C

Each block contributes `s · weight · (4 lanes · S²)`.

- **`Re(D)`: `C = 0`.** Every `+ re·re` block is paired with an `− im·im` block of **identical weight and S** (same nibble types, only the part differs), so their constants cancel term-by-term → total **0**.
- **`Im(D)`: `C = 1 297 680 384`.** All 32 blocks are `+`; within each row the two `re·im` and `im·re` blocks share weight and S, so `C = Σ_blocks weight·4S²` with no cancellation. (Injected once at the accumulator for the imaginary output.)

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves `PE`, `α`, and `β` for both `Re(D)` and `Im(D)` — the complex mode reuses the same primitive, only operand routing, weights, sign, and `C` differ.
- **Centering** flips the MSB of each **unsigned** nibble (`a_L^hi`, `a_H^lo`, `a_L^lo`, `b^hl`, `b^lh`, `b^ll`); the signed nibbles (`a_H^hi`, `b^hh`) are not flipped. Shared by the PE and the α/β generators (dispatcher output).
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): `A → A−8`, `B → B−8` (S=8) and `A → A−16`, `B → B−16` (S=16). See [square_basics.tex](./square_basics.tex).
- **Negation** of the `a^im·b^im` group is a per-block sign at the accumulator (PE, α, β, C alike); no extra square/generator hardware.
- `C` is a per-mode constant injected once at the accumulator: `0` for `Re(D)`, `1 297 680 384` for `Im(D)`.
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

Take all four lanes equal to `a^re=5, a^im=3, b^re=2, b^im=7` (so `a=5+3j`, `b=2+7j`, `a·b = −11+41j`, summed over 4 lanes):

```
Re(D) = 4·(5·2 − 3·7) = 4·(−11) = −44
Im(D) = 4·(5·7 + 3·2) = 4·( 41) = 164
```

The reconstruction `½(PE−α−β+C)` from each box reproduces both exactly. Illustrating the two centering rows on single nibble products:

```
signed·signed  A=−1,B=−1 :  ½( (−1+−1)² − (−1)² − (−1)²        )     = ½(4−1−1)        =   1   [= (−1)(−1)]
unsigned·unsigned A=15,B=7 : ½( ((15−8)+(7−8))² − (15−16)² − (7−16)² + 256 ) = ½(36−1−81+256) = 105  [= 15·7]
```

For an `im·im` block the same `½(…)` is formed with **add-square** and then **subtracted** (minus outside), yielding `−A·B`. The companion verifier exercises **81 296** vectors — random int16 parts plus corners `0, −1, 0x7F, −128, 0xFF, ±32768` — and confirms both `Re(D)` and `Im(D)` reconstruct, with every square argument in `[−16,15]`.
