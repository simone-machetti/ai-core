# Mode 11 — Square (centered / opt)

Companion notes to [mode_11_opt.tex](./mode_11_opt.tex). General cases and the bit-level hardware are in [square_basics.tex](./square_basics.tex); the baseline (uncentered) square sheet is [mode_11.tex](./mode_11.tex).

Mode 11 is a **complex int8 dot product** `C-DP16(C8×C8)` over 16 complex lanes:

```
D = Σ_{i=0..15} a_i · b_i      a_i = a^re_i + j·a^im_i,  b_i = b^re_i + j·b^im_i
```

Each of `a^re, a^im, b^re, b^im` is an **int8**. Splitting the complex multiply:

```
Re(D) = Σ a^re·b^re − Σ a^im·b^im      (the a^im·b^im group is NEGATED)
Im(D) = Σ a^re·b^im + Σ a^im·b^re      (all +)
```

The square variant replaces each per-lane nibble multiply with an **add-then-square** on centered ≤5-bit operands, compensating with an A-only term `α`, a B-only term `β`, and a constant `C`. Re(D) and Im(D) are produced as **separate boxes**, each with its own `PE, α, β, C`:

```
Re(D) = ½ · (PE − α − β + C)          Im(D) = ½ · (PE − α − β + C)
```

"Centered / opt" = each **unsigned** nibble is biased by **−8** (flip its MSB) before the square, so every square is **5-bit-in / 9-bit-out** (arg ∈ [−16,14] for PE, [−16,7] for α/β).

## Nibble split & signedness

Each int8 part `X` splits into hi/lo nibbles, and only its **top** nibble is signed:

- `a^re = 2⁴·a_H^re + a_L^re` — `a_H^re` signed, `a_L^re` **unsigned**. Same for `a^im, b^re, b^im` (`b`'s nibbles are named `b^{·,hi}` / `b^{·,lo}`).

The four operands `a^re, a^im, b^re, b^im` are **independent** — each contributes its own signed top nibble and unsigned low nibble. So every per-lane real product (e.g. `a^re·b^re`) becomes **four** nibble products spanning all four signedness combos.

## Per-block table (the four nibble combos)

Every real dot-product group is a full **int8×int8 DP16**, laid out (as in the baseline) as 4 nibble-type blocks × 2 halves (i = 0..7, 8..15) = **8 blocks**. `au`/`bu` = A/B-nibble unsigned flags; `S = 8(au+bu)`; per-lane `C = S²`.

| block | weight | au bu | formula | PE arg | α = (A−S)² | β = (B−S)² | C / lane |
|---|---|---|---|---|---|---|---|
| `a_H·b^hi` | 2⁸ | 0 0 | (1) both signed | `(a_H + b^hi)²` | `a_H²` | `(b^hi)²` | 0 |
| `a_L·b^hi` | 2⁴ | 1 0 | (3) A unsigned | `((a_L−8) + b^hi)²` | `(a_L−8)²` | `(b^hi−8)²` | 64 |
| `a_H·b^lo` | 2⁴ | 0 1 | (3) B unsigned | `(a_H + (b^lo−8))²` | `(a_H−8)²` | `(b^lo−8)²` | 64 |
| `a_L·b^lo` | 2⁰ | 1 1 | (5) both unsigned | `((a_L−8) + (b^lo−8))²` | `(a_L−16)²` | `(b^lo−16)²` | 256 |

Weights come from `a·b = (2⁴a_H + a_L)(2⁴b^hi + b^lo)`. This block table is identical to mode 2 (real int8×int8) — mode 11 just applies it four times, once per real product.

## Groups & signs

| box | group | product | sign | # blocks |
|---|---|---|---|---|
| `Re(D)` | re·re | `a^re·b^re` | **+** | 8 |
| `Re(D)` | im·im | `a^im·b^im` | **−** | 8 |
| `Im(D)` | re·im | `a^re·b^im` | **+** | 8 |
| `Im(D)` | im·re | `a^im·b^re` | **+** | 8 |

**Negation (im·im in Re):** the baseline writes `−Σ a^im·b^im` as a *subtract*-square `(x−y)²`. That does **not** survive centering. Instead the negated group keeps the ordinary **add**-square `((x−δx)+(y−δy))²`, and the **whole block** carries a minus — so its `PE`, `α`, `β` **and** `C` all appear with `−` (identically). This is the only structural difference from a positive group.

## Components

Within a box, `PE`, `α`, `β` are the weighted sums over that box's 16 blocks (2 groups × 8 blocks); each per-block term is taken from the table, summed over the block's 8 lanes, and multiplied by the block's group sign:

```
PE = Σ_blocks  sign · weight · Σ_lanes (PE arg)
α  = Σ_blocks  sign · weight · Σ_lanes (α term)
β  = Σ_blocks  sign · weight · Σ_lanes (β term)
Result = ½ · (PE − α − β + C)
```

Because `−w·(x·y) = ½((−w·PE_b) − (−w·α_b) − (−w·β_b) + (−w·C_b))`, negating a whole block is exactly "put `−` on all four of PE/α/β/C", which is why the reconstruction rule `½(PE−α−β+C)` is unchanged.

- `α` (A-side) uses `a_H^re, a_L^re` (from the re group) and `a_H^im, a_L^im` (from the im group); in `Re(D)` the im-side α terms are **negated**, in `Im(D)` all are `+`.
- `β` (B-side) uses each group's b-part nibbles: `Re(D)` → `b^{re,·}` (+) and `b^{im,·}` (−); `Im(D)` → `b^{im,·}` (+) and `b^{re,·}` (+).

## Constant C

Each group is a full int8×int8 DP16, whose per-block constants (weight × 8·S²) are

```
0 + 8192 + 0 + 8192 + 8192 + 2048 + 8192 + 2048 = 36864
```

Applying the group signs:

```
Re(D):  C = (+36864) − (36864) = 0
Im(D):  C = (+36864) + (36864) = 73728
```

So `Re(D)` needs **no** constant; `Im(D)` injects **73728**.

## Hardware notes

- One **5-bit-in / 9-bit-out** square serves PE, α, and β across all blocks and both boxes — same primitive as modes 1/2, only operands, weights, signs and `C` differ.
- Centering: flip the MSB of each **unsigned** nibble (`a_L^{re/im}`, `b^{re/im,lo}`); signed top nibbles are not flipped. Shared by PE and generators (dispatcher output).
- Each generator adds the **removed** operand's `−8` on its own input (2-gate top-bit remap): `a_H→a_H−8`, `b^hi→b^hi−8` (S=8 blocks) and `a_L→a_L−16`, `b^lo→b^lo−16` (S=16 blocks). See [square_basics.tex](./square_basics.tex).
- The im·im group's minus is a **sign flip at accumulation** (PE, α, β, C of that group all subtract) — no new datapath, the same negation the baseline already applies to `−Σ a^im·b^im`.
- `C` is a per-mode/per-output constant injected once at the accumulator: `Re(D)` → 0, `Im(D)` → 73728.
- In the grid, `α` is amortized per row (A-only) and `β` per column (B-only).

## Numeric check

Single active lane `i=0`, all others zero, with `a^re = a^im = b^re = b^im = 0xFF = −1` (so `a_H=b^hi=−1`, `a_L=b^lo=15` for every part). Each of the four real products is the int8×int8 `(−1)·(−1) = 1`, reconstructed via the four nibble blocks exactly as in mode 2:

```
a_H·b^hi (00,f1): ½(4 − 1 − 1 + 0)       =   1 , ×2⁸ = +256
a_L·b^hi (10,f3): ½(36 − 49 − 81 + 64)   = −15 , ×2⁴ = −240
a_H·b^lo (01,f3): ½(36 − 81 − 49 + 64)   = −15 , ×2⁴ = −240
a_L·b^lo (11,f5): ½(196 − 1 − 1 + 256)   = 225 , ×1  = +225
                                    per-group total = 1
```

Combine with group signs:

```
Re(D) = (re·re) − (im·im) = 1 − 1 = 0     true: (−1)(−1) − (−1)(−1) = 0   ✓
Im(D) = (re·im) + (im·re) = 1 + 1 = 2     true: (−1)(−1) + (−1)(−1) = 2   ✓
```

The generator's verifier (`gen_mode11.py`) checks both `Re(D)` and `Im(D)` against `½(PE−α−β+C)` over 400 vectors (random int8 parts plus corners `0, ±1, 0x7F, −128, 0xFF, min/max`): **all pass**, every square argument stays in `[−16,14]`, and `C = 0` (Re) / `73728` (Im).
