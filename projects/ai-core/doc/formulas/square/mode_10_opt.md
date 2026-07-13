# Mode 10 — Square (centered / opt)

Companion notes to [mode_10_opt.tex](./mode_10_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_10.tex](./mode_10.tex).

Mode 10 is a **complex int8 × int8** dot product, `C-DP8(C8×C8)`, over 8 lanes:

```
D = Σ_{i=0..7} a_i · b_i        a_i = a^re_i + j·a^im_i ,  b_i = b^re_i + j·b^im_i
Re(D) = Σ a^re·b^re  −  Σ a^im·b^im       (the a^im·b^im group is NEGATED)
Im(D) = Σ a^re·b^im  +  Σ a^im·b^re       (all +)
```

Each of `a^re, a^im, b^re, b^im` is an **independent int8**. The square variant replaces each per-lane multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`, computed **separately for Re(D) and Im(D)**:

```
Re(D) = ½ · (PE − α − β + C)    Im(D) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

Every int8 part splits into hi/lo nibbles; only the **high** nibble is signed:

- `a^re = 2⁴·a_H^re + a_L^re`, `a_H^re` signed, `a_L^re` **unsigned**. Same for `a^im`.
- `b^re = 2⁴·b^{re,hi} + b^{re,lo}`, `b^{re,hi}` signed, `b^{re,lo}` **unsigned**. Same for `b^im`.

So every real product group (e.g. `a^re·b^re`) is **4 DP8(4×4) blocks** of weights `2⁸ / 2⁴ / 2⁴ / 1` — like a single 8-lane group of mode 2. Re(D) is **8 blocks** (4 for `a^re·b^re`, 4 for `a^im·b^im`); Im(D) is **8 blocks** (4 for `a^re·b^im`, 4 for `a^im·b^re`).

## The negated group (`−Σ a^im·b^im`)

The baseline writes this group as a **subtract**-square `(x−y)²`, which does not survive centering. In the opt form each of its 4 blocks keeps the ordinary **add**-square `((x−δx)+(y−δy))²`, but the **whole block carries a global minus** — so those blocks appear with `−` in **PE, α, β AND C** identically. Everything else (`a^re·b^re` in Re; both groups of Im) is `+`.

## Per-block table (one product group = 4 blocks)

`au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`. `A` is the a-side nibble, `B` the b-side nibble. Each block is summed over its 8 lanes. Negated group: multiply the whole row (PE, α, β, C/lane) by `−1`.

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C / lane |
|---|---|---|---|---|---|---|---|
| `A_H·B_hi` | 2⁸ | 0 0 | (1) both signed | `(A_H + B_hi)²` | `A_H²` | `B_hi²` | 0 |
| `A_L·B_hi` | 2⁴ | 1 0 | (3) A unsigned | `((A_L−8) + B_hi)²` | `(A_L−8)²` | `(B_hi−8)²` | 64 |
| `A_H·B_lo` | 2⁴ | 0 1 | (3) B unsigned | `(A_H + (B_lo−8))²` | `(A_H−8)²` | `(B_lo−8)²` | 64 |
| `A_L·B_lo` | 2⁰ | 1 1 | (5) both unsigned | `((A_L−8) + (B_lo−8))²` | `(A_L−16)²` | `(B_lo−16)²` | 256 |

Weights: `A·B = (2⁴A_H + A_L)(2⁴B_hi + B_lo) = 2⁸ A_H B_hi + 2⁴ A_H B_lo + 2⁴ A_L B_hi + A_L B_lo`.

## Components

`PE`, `α`, `β` are the signed weighted sums over the 8 blocks of each box (the `a^im·b^im` blocks of Re carry `−`; all others `+`); each per-block term is taken from the table above, summed over that block's lanes:

```
PE = Σ_blocks  ±weight · Σ_lanes (PE arg)
α  = Σ_blocks  ±weight · Σ_lanes (α term)
β  = Σ_blocks  ±weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

The same nibble appears squared several ways because its partner varies: e.g. in `α`, `a_H^re` gives `a_H^re²` (paired with `b^{re,hi}`, S=0) **and** `(a_H^re−8)²` (paired with `b^{re,lo}`, S=8); `a_L^re` gives `(a_L^re−8)²` and `(a_L^re−16)²`. The extra `−8` on a signed nibble is the **removed operand's biased zero** — see [square_basics.tex](./square_basics.tex) for the `α = PE(A,0)` / `β = PE(0,B)` derivation.

## Constant C

Each block contributes `±weight × (8 lanes × S²)`, with `8·S² ∈ {0, 512, 2048}`:

| block | weight | 8·S² | contribution |
|---|---|---|---|
| `A_H·B_hi` | 2⁸ | 0 | 0 |
| `A_L·B_hi` | 2⁴ | 512 | 8192 |
| `A_H·B_lo` | 2⁴ | 512 | 8192 |
| `A_L·B_lo` | 2⁰ | 2048 | 2048 |

**Im(D)** — both groups add, so `C` is two copies of the (0, 8192, 8192, 2048) pattern:

```
C(Im) = 0 + 8192 + 0 + 8192  +  8192 + 2048 + 8192 + 2048 = 36864
```

**Re(D)** — the `a^re·b^re` group adds and the `a^im·b^im` group subtracts the **identical** constants, so they cancel exactly:

```
C(Re) = 0 + 8192 + 0 − 8192  +  8192 + 2048 − 8192 − 2048 = 0
```

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β — unchanged from modes 1/2; only the operands, weights, signs, and `C` differ.
- Centering: flip the MSB of each **unsigned** nibble (`a_L^{re/im}`, `b^{re/im,lo}`) at the dispatcher; signed nibbles (`a_H`, `b^{hi}`) are not flipped. Shared by PE and the α/β generators.
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): `A_H → A_H−8`, `B_hi → B_hi−8` (S=8 blocks); `A_L → A_L−16`, `B_lo → B_lo−16` (S=16 blocks).
- The `a^im·b^im` group is subtracted by driving its PE/α/β/C accumulation with a global sign flip — the block content is an ordinary add-square, so no special square is needed for it.
- `C(Re) = 0` and `C(Im) = 36864` are per-mode constants injected once at the accumulator (not per lane).
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

One lane with `a^re = 0xFF = −1` (`a_H^re=−1, a_L^re=15`), `a^im = 0x01 = 1` (`a_H^im=0, a_L^im=1`), `b^re = 0x7F = 127` (`b^{re,hi}=7, b^{re,lo}=15`), `b^im = 0xFF = −1` (`b^{im,hi}=−1, b^{im,lo}=15`):

True: `Re = a^re·b^re − a^im·b^im = (−1)(127) − (1)(−1) = −126`; `Im = a^re·b^im + a^im·b^re = (−1)(−1) + (1)(127) = 128`.

**Re(D)** — `a^re·b^re` group (`+`):

```
A_H·B_hi (00): ½(36 − 1 − 49 + 0)     =  −7 , ×2⁸ = −1792   [(−1+7)²=36]
A_L·B_hi (10): ½(196 − 49 − 1 + 64)   =  105, ×2⁴ = +1680   [((15−8)+7)²=196]
A_H·B_lo (01): ½(36 − 81 − 49 + 64)   =  −15, ×2⁴ =  −240   [(−1+(15−8))²=36]
A_L·B_lo (11): ½(196 − 1 − 1 + 256)   =  225, ×1  =  +225
                                    group sum = −127 = (−1)(127) ✓
```

`a^im·b^im` group (**global `−`**):

```
A_H·B_hi (00): ½(1 − 0 − 1 + 0)       =   0 , ×2⁸ =    0
A_L·B_hi (10): ½(64 − 49 − 81 + 64)   =  −1 , ×2⁴ =  −16
A_H·B_lo (01): ½(49 − 64 − 49 + 64)   =   0 , ×2⁴ =    0
A_L·B_lo (11): ½(0 − 225 − 1 + 256)   =  15 , ×1  =  +15
                                    group sum =  −1 = (1)(−1)
Re(D) = (−127) − (−1) = −126  ✓
```

`Im(D)` reconstructs to `+128` the same way (both groups added). A brute-force check over 25k random + corner operand vectors (`verify_mode10.py`) confirms both boxes for all cases, with every square argument in `[−16,14]`.
