# Square variant — implementation reference

Design/implementation notes for the **square** variant (`_sqr`) of the reconfigurable MatMul PE: replace the per-lane **multiply** inside each `DP8` with an **add-then-square** on centered 4-bit nibbles, and compensate outside the squarer with per-row `α`, per-column `β`, and a per-mode constant `C`. External behaviour of the PE and the N×N grid is unchanged.

This file is the single place to look when implementing. Companion material in the same folder: the general math in [square_basics.tex](./square_basics.tex), the per-mode formula sheets [mode_N_opt.tex](./mode_1_opt.tex)/`.pdf` and notes `mode_N_opt.md`. Staged build plan: the `_sq` plan in `.claude/plans/`.

**Naming:** the variant suffix is `_sqr` (e.g. `dp_8_sqr`, `disp_array_a_sqr`, `top_NxN_sqr`). Operands are **centered at the dispatcher**, so the square datapath (`dp_8_sqr`, `pe_array_sqr`) works on pre-centered signed nibbles and carries **no `is_signed`**.

---

## 1. Core identity

For a per-lane product `x·y` (x = an a-side nibble, y = a b-side nibble):

```
x·y = ½[ (x+y)² − x² − y² ]                      (add-and-square)
```

Dot-product / DP8(4×4) form over 8 lanes, then folded through the existing **linear** reduction tree `L(·)`:

```
Result = ½ ( PE − α − β + C )
  PE = L({ Σ(x+y)²  per DP8(4×4) block })     ← per-PE squares
  α  = L({ Σ x²  })                            ← A-only  (shared per row)
  β  = L({ Σ y²  })                            ← B-only  (shared per column)
  C  = L({ per-block constant })               ← per-mode constant
```

`÷2 is exact`: the bracket `PE − α − β + C` always equals `2·Result`, so its LSB is provably 0.

### Split-then-square (why it is small)
Split each int8 `a = 2⁴·a_H + a_L`, turning the 8×4 multiply into two 4×4 products, each done as an add-then-square on ~5-bit operands. The squarer is a **5-bit-in / 9-bit-out** unit ([s_5_bit_sqr](../../../rtl/s_5_bit_sqr.sv)) — the whole area/power bet is that `2×(5-bit square + 5-bit adder) < 1× int8×int4 Booth multiply` per lane (to be settled by synthesis).

---

## 2. Centering (excess-8) — keeps every square 5-bit

Each 4-bit nibble is **centered** before the square: SIGNED nibbles unchanged; UNSIGNED nibbles biased by `−8` (flip the MSB) so both land in `[−8,7]`. With `δx, δy ∈ {0,8}` and `S = δx+δy`:

```
x·y = ½[ ((x−δx)+(y−δy))²  −  (x−S)²  −  (y−S)²  +  S² ]
```

- `PE` argument `(x−δx)+(y−δy) ∈ [−16,14]`  → 5-bit signed.
- `α,β` arguments `(x−S),(y−S) ∈ [−16,7]`   → 5-bit signed.
- square output ∈ `[0,256]`                  → **9-bit unsigned**.

**Verified**: across all 11 modes and all corner inputs, every square argument stays in `[−16,14] ⊂ [−16,15]`. One 5-bit-in / 9-bit-out square serves PE, α and β.

### The three cases (by number of unsigned nibbles `u`)

`S = 8u`, per-lane `C = S²`, block constant = `Nlanes · S²`.

| u   | (x,y) | S   | formula | PE               | α=(x−S)²  | β=(y−S)²  | C/lane |
| --- | ----- | --- | ------- | ---------------- | --------- | --------- | ------ |
| 0   | s,s   | 0   | (1)     | `(x+y)²`         | `x²` (4b) | `y²` (4b) | 0      |
| 1   | u,s   | 8   | (3)     | `((x−8)+y)²`     | `(x−8)²`  | `(y−8)²`  | 64     |
| 1   | s,u   | 8   | (3)     | `(x+(y−8))²`     | `(x−8)²`  | `(y−8)²`  | 64     |
| 2   | u,u   | 16  | (5)     | `((x−8)+(y−8))²` | `(x−16)²` | `(y−16)²` | 256    |

Rows `u=1` (`u,s` vs `s,u`): α and β are both `x−8`/`y−8`, but the widths swap (the signed operand's `−8` lands in `[−16,−1]` = 5b; the unsigned operand's `−8` lands in `[−8,7]` = 4b). The 5-bit unit covers both.

The `−8` on a signed operand's α/β (e.g. `(y−8)²` when y is signed) is the **removed operand's biased zero**: `α = PE(x,0)`, `β = PE(0,y)`, and zeroing an *unsigned* operand still centers it to `−8`.

---

## 3. Signedness rule and per-mode mapping

**Rule**: for each independent operand, ONLY its single most-significant nibble is SIGNED (δ=0); every lower nibble is UNSIGNED (δ=8, biased −8).
- int4 operand: its one nibble is signed.
- int8 `X` → `X_H` (signed), `X_L` (unsigned).
- int16 `X` → `X_H^hi` (signed), `X_L^hi, X_H^lo, X_L^lo` (unsigned).
- complex: `a^re, a^im, b^re, b^im` are each independent operands (top nibble signed, rest unsigned).

This matches the datapath's per-slice signedness ([ctrl](../../../rtl/ctrl.sv) `IS_SIGNED_A_LUT`/`IS_SIGNED_B_LUT`, MSB slice signed) and is what keeps every square in 5-bit. Correctness of `½(PE−α−β+C)=Result` holds for *any* centering; the signedness choice only governs the bit-width. In the square variant these `is_signed_a/b` buses are routed to the **dispatchers** (they drive centering there), not to the square datapath.

### Per-mode constant `C` (verified)

| mode | kind    | operands             | `C`                     |
| ---- | ------- | -------------------- | ----------------------- |
| 1    | real    | int8×int4 (16 lanes) | 1 024                   |
| 2    | real    | int8×int8 (16)       | 36 864                  |
| 3    | real    | int16×int8 (8)       | 4 892 672               |
| 5    | real    | int8×int4 (32)       | 2 048                   |
| 6    | real    | int8×int8 (32)       | 73 728                  |
| 7    | real    | int16×int8 (16)      | 9 785 344               |
| 8    | real    | int16×int16 (16)     | 2 595 360 768           |
| 9    | real    | int16×int16 (8)      | 1 297 680 384           |
| 10   | complex | C8×C8 (8)            | Re 0 · Im 36 864        |
| 11   | complex | C8×C8 (16)           | Re 0 · Im 73 728        |
| 12   | complex | C16×C16 (4)          | Re 0 · Im 1 297 680 384 |

`C` is data-independent → precompute per mode (a small LUT / constant) and inject once at the accumulator. Block constant = `weight × Nlanes × S²`; `Nlanes` is 8 per DP8(4×4) **except mode 12** (`C-DP4`, `Nlanes = 4`, so block const uses `4·S²`). `C` is computed over the **active** lanes only — idle DP8s must contribute nothing (see below), which is what keeps these values correct.

### Idle lanes (modes 5/6 zero-gating) — must be a *real* zero

Only modes 5/6 idle-gate (zero) DP8s. **A zeroed lane does not self-cancel in general** — this is the correction to the earlier "no special handling" claim:

- Zeroing `b` then centering an *unsigned* nibble gives `b_c = −8`, so the PE squares `(a_c−8)² ≠ 0` and the β generator adds `S²`. `PE − α` cancels (data-independent, since the idle DP8's A feeds both), but the residual `−β = −S²` leaks unless `C` includes that idle lane's `S²` — and `C` is active-only.
- **Mode 5** idle DP8s have `bu=1` (unsigned `b`) → `S=8`, `β=64`/lane, uncancelled → a `−32`/lane error. **Mode 6** idle DP8s have signed `b` (`bu=0`) → `S=0` → already clean. That one bit (idle-`b` signedness) is the whole difference.

**Fix — make each idle DP8 a true hardware zero, contributing nothing to `PE`, `α`, `β`, or `C`:**
1. The dispatchers zero **both** `a_dp8_o` and `b_dp8_o` for idle DP8s (a per-DP8 `zero_i`, applied *after* centering). The PE then squares `(0+0)²=0` — no toggling — and the α/β generators, fed the same zeroed buses, see `0` on their live side.
2. Treat idle DP8s as **signed** so the removed-operand bias vanishes: `is_signed_b = 1` on the idle DP8s (mode 5's are the only unsigned-`b` idle DP8s — set them to signed; mode-5 `b` is signed anyway, so these were baseline don't-cares). Then the α remap's `−8·bu = 0` → `α = 0`; `is_signed_a` is already 1 there → `β = 0`.

Result: idle DP8s add nothing anywhere, `C` stays the active-only value the sheets give, and **`pe_array_sqr` needs no idle logic** — it's all in the dispatcher (`zero_i` on both gates) + the `is_signed_b` LUT. See §7 for the gate/dispatcher modules.

---

## 4. Complex negation — the key finding

Complex modes (10/11/12) have negated products, e.g. `Re(D) = Σ a^re·b^re − Σ a^im·b^im`.

**Uncentered**, negation is free via *subtract-and-square*: `−x·y = ½[(x−y)² − x² − y²]`, with α=x², β=y² unchanged (sign-blind, since `(−y)²=y²`). The baseline formula sheets and the baseline multiply datapath both rely on this.

**Under centering this breaks.** α/β carry a *directional* `−8` that cancels a specific linear term; flipping the product sign flips the sign of the linear term needed, but the shared α/β still cancel the old sign → they double it → a **data-dependent leftover** `4δx·y + 4δy·x`, which cannot be a constant `C`. (Verified: the required "constant" scatters over `{…,−160,…,32,…}`.) Note this afflicts *subtract*-and-square only — **operand pre-negation** (feeding `−y` and using add-and-square) has no such mismatch, because `α/β/C` are then computed from the *fed* data (this is what mode 12 uses, below).

**Fix — negate the whole compensated block:**
```
−x·y = −½(PE − α − β + C) = ½(−PE + α + β − C)
```
with the SAME `PE=(x_c+y_c)²` (still **add-and-square**), the SAME `α=(x−S)²`, `β=(y−S)²`, `C=S²`. Only the block's **accumulation sign** flips → in the box, negated blocks carry `−` on PE, α, β AND C identically.

Consequences:
- The squarer is **always add-and-square** (no subtract mode).
- The α/β generators are **fully shared** between `+` and `−` blocks.
- **`C(Re)=0`** for every complex mode: each `+re·re` block pairs with a `−im·im` block of equal weight and signedness, so their constants cancel. `C(Im)` = 2× the per-group constant.
- Verified numerically for Re(D) and Im(D) of all three complex modes.

### Modes 10/11 vs mode 12 — two different negation mechanisms
- **Modes 10/11 (C8×C8):** `re·re` and `im·im` land in **separate whole DP8s**, so the sign is a whole-DP8 negate — done today by `gate_b_n` negating `b^im`, and **relocated** in the square variant into the tree ([pe_array_sqr](../../../rtl/pe_array_sqr.sv), §7). The negate is a carry-save **one's-complement** of the block's `(sum,carry)` pair (`~sum, ~carry`), which resolves to `−S_DP8−2`; the leftover `+2` per negated block (data-independent) folds into `C`. Across modes 10/11 the negated blocks are always DP8 **{2,3,6,7,10,11}** — the six lo (`CX1`) legs of L0 nodes 0–5 — so the control is a **6-bit `neg`** (one per negatable L0 node), not one per DP8. The α/β generators carry the same 6-bit `neg` on their matching reduction legs.
- **Mode 12 (C16×C16):** each `Re(D)` DP8(8×4) block **mixes** 4 `+re·re` lanes and 4 `−im·im` lanes — a *per-lane* sign that a whole-DP8 negate cannot express. The baseline realizes it by **software pre-negation**: the caller stores `−b^im` in the operand ([tb_pe_array](../../../tb/tb_pe_array.sv) `pack_b_c16c16`), so `CTR[12]` is all-pass. This is **kept unchanged** in the square variant — operand pre-negation is `a·(−b) = −a·b` via ordinary add-and-square, `α/β/C` computed from the fed (already-negated) data (no §4 breakage). So mode 12 needs **no hardware negate**; the caller keeps pre-negating `b^im`.

---

## 5. Bit-level hardware for centering (+ idle-zero)

The bias is one primitive: **flip the nibble MSB** (the weight-8 bit) → `−8`, converting unsigned→signed. One XOR per nibble MSB, gated by the **unsigned flag** `~is_signed` (flip iff unsigned — polarity confirmed). There is **no separate `−16`** operation.

### Where each piece lives

| logic                                  | what                                                             | where                                                 | shared?                                                               |
| -------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------- |
| `−8` MSB-flip (centering → `x_c, y_c`) | flip nibble MSB iff unsigned                                     | **dispatcher output** (`gate_a_n_sqr`/`gate_b_n_sqr`) | per row (a), per column (b) — identical for PE and α/β, so do it once |
| idle-zero (`zero_i`)                   | force `a_dp8_o = b_dp8_o = 0` for idle DP8s, **after** centering | **same gates**                                        | per-DP8; makes idle a real zero (§3)                                  |
| α/β `−S` completion (the `−16` bit)    | removed operand's extra `−8`                                     | **α/β generator input**                               | per generator (2 gates)                                               |
| add + 5-bit square                     | —                                                                | PE / α / β cores (identical)                          | —                                                                     |
| constant `C`                           | per-mode                                                         | acc-array injection                                   | grid-wide (one per mode)                                              |

The A operand centers **both** nibbles of each int8: low nibble (`a[3]`) MSB is flipped **always** (a low nibble is never a MSN → always unsigned); high nibble (`a[7]`) MSB is flipped iff `~is_signed_a`. The B nibble (`b[3]`) is flipped iff `~is_signed_b`. Because the square datapath receives these pre-centered nibbles, `dp_8_sqr` carries no `is_signed` and does no flipping.

### α/β generator remap (optimized, other operand removed)
The `−16` is never a real `−16`: it is two `−8`s summed. In the optimized generator (the removed operand's path is gone, so there is no adder to add the second `−8`), apply the total bias `S` to the top two bits of the live operand (β shown; α is symmetric with the removed-operand flag as the OR term). `au = ~is_signed_a`, `bu = ~is_signed_b`:

```
β_arg[2:0] = y[2:0]                       (pass through)
β_arg[3]   = y[3] XOR au XOR bu
β_arg[4]   = au OR (y[3] XOR bu)
```

Truth table (β; `y3 = y[3]`):

| au bu | S   | β_arg[4] β_arg[3] | value                           |
| ----- | --- | ----------------- | ------------------------------- |
| 0 0   | 0   | `y3 y3`           | `y` (sign-extended)             |
| 0 1   | 8   | `~y3 ~y3`         | `y−8` (y unsigned = MSB-flip)   |
| 1 0   | 8   | `1 ~y3`           | `y−8` (y signed)                |
| 1 1   | 16  | `1 y3`            | `y−16` (y unsigned = set bit 4) |

So the `−16` case (both unsigned) is literally "set bit 4" (prepend a `1` to the raw unsigned nibble). Two gates on the top bits; low 3 bits pass through. No adder needed.

**Formula-3 sanity (row `1 0`, x unsigned / y signed):** the PE sees `y` normal (`y_c = y`, no flip because y is signed); β sees `y−8`. The `−8` in β is the removed x's biased zero, applied only in the β generator — this is why the centering `−8` is shared at the dispatcher while the `−S` completion stays inside α/β.

**Built** (the remap on the *dispatched* nibble): since the generator receives the already-centered `A_c`/`B_c` (`[−8,7]`), the remap reduces to a **conditional single `−8`** on the top two bits — `is_signed ? {n3,n} : {1,~n3,n[2:0]}` — realized by [gate_n_sqr](../../../rtl/gate_n_sqr.sv) (flag-selected) and [gate_n_beta_sqr](../../../rtl/gate_n_beta_sqr.sv) (fixed + idle-zero, for the β low block). This is equivalent to the raw-input table above (`A_c3 = A3 ⊕ au`), just with the dispatcher's `−8` pre-applied. See [Alpha/beta generators — built](#alphabeta-generators--built).

---

## 6. Baseline RTL — what exists today (read before changing)

Files in [rtl/](../../../rtl/). The baseline has since been refactored to shared control/dispatch (one `ctrl`, per-row `disp_array_a`, per-column `disp_array_b`, `pe` cores in the `top_NxN` grid). Relevant structure:

- **`disp_array_a.sv`** — A-path dispatch (per row): input reg + 8× `mux_n` (4→1 block select), broadcast to the pair. **No gate** (A is never gated/negated today).
- **`disp_array_b.sv` + `gate_b_n.sv`** — B-path dispatch (per column). `gate_b_n` codes (2-bit `sel`): `00` pass, `01` zero (idle lanes), `10` `GATE_NEG`, `11` `GATE_NEG_CARRY`. Negating an int8 B negates its two int4 nibbles across two halves: low nibble `GATE_NEG`, high nibble `GATE_NEG_CARRY` (carry chained low→high) for an exact full-width two's-complement.
- **`ctrl.sv`** — shared per-mode LUTs. `CTR_L_LUT`/`CTR_H_LUT` drive the B-gate codes: `2'd1` (zero) on the idle-lane modes (5/6); `2'd2`/`2'd3` (NEG / NEG_CARRY) on the **complex** entries 10/11 imaginary pairs → the complex minus of 10/11 is `b^im` negation. Entry 12 is all-pass (mode 12 uses SW pre-negation, §4). `IS_SIGNED_A_LUT`/`IS_SIGNED_B_LUT` give per-DP8 signedness (MSB slice signed).
- **`dp_8.sv`** — the primitive being replaced. Ports: `a_i[8×int8]`, `b_i[8×int4]`, `is_signed_a_i`, `is_signed_b_i`, → 20-bit carry-save `sum_o`/`carry_o` (16-bit value + 4 guard, sign-consistent).
- **`pe_array.sv`** — instantiates 16 `dp_8` and reduces their carry-save outputs through a **purely additive** 4-level CPR-4:2 tree (`node = prev + shift`, shifts 8/4/8/– at L0..L3, all `IS_SIGNED=1` = sign-extension only). Node widths 28/32/40/40; carry-save taps 18/29/37/38 exported at every level. **No subtract, no per-block sign anywhere in the tree.** L0 is registered.
- **`acc_array.sv`** — resolves/accumulates the tap; folds a 3rd CPR row via the `acc_i`/`sel_acc` mux (seed OR feedback, exclusive).
- **`pe.sv` / `top_NxN.sv`** — self-contained PE core, and the N×N grid.

**Key takeaway:** today the complex sign (10/11) is *operand negation* in `disp_array_b`; the tree only adds. That is the *subtract-and-square*-style path that centering forbids for the square math, so it must relocate (§4, §7).

---

## 7. Required changes, module by module

| module                                                                                                              | status             | change                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`s_5_bit_sqr.sv`**                                                                                                | **built**          | flat K-map-minimized signed 5-bit squarer (`[−16,15]` → unsigned `[0,256]`; only `−16` sets the 9th bit). 16 instances per `dp_8_sqr`.                                                                                                                                                                                                                                                                                                                      |
| **`dp_8_sqr.sv`**                                                                                                   | **built — Gate 1** | drop-in DP8 for the square path. Takes **pre-centered** signed nibbles (`a_i`/`b_i`, **no `is_signed`, no clk**), splits `a` into `{AH,AL}`, 5-bit signed add, 16× `s_5_bit_sqr`, 2× **unsigned** `cpr_w_n` 8:2 (EXT=3→12b) + AH `<<4` + **unsigned** `cpr_w_n` 4:2 (EXT=2) → **18-bit unsigned** carry-save `S_DP8` (raw square-sum; **no α/β/C/÷2**). Non-negative → **no sign-consistency contract** (the hardest `dp_8` property vanishes).             |
| **`gate_a_n_sqr.sv`** (NEW)                                                                                         |                    | A centering + idle-zero (`WIDTH=8, SIZE=8`): per int8, `out = zero_i ? 0 : {in[7]^~is_signed, in[6:4], ~in[3], in[2:0]}`. Combinational.                                                                                                                                                                                                                                                                                                                    |
| **`gate_b_n_sqr.sv`** (NEW, replaces `gate_b_n`)                                                                    |                    | B centering + idle-zero (`WIDTH=4, SIZE=8`): per int4, `out = zero_i ? 0 : {in[3]^~is_signed, in[2:0]}`. **No negate, no carry chain.**                                                                                                                                                                                                                                                                                                                     |
| **`disp_array_a_sqr.sv`** (NEW, replaces `disp_array_a`)                                                            |                    | + `is_signed_a_i[0:15]`, + `zero_i[0:15]`; input reg → 8 `mux_n` → **16 `gate_a_n_sqr` (per-DP8)**. Centers A + zeros idle.                                                                                                                                                                                                                                                                                                                                 |
| **`disp_array_b_sqr.sv`** (NEW, replaces `disp_array_b`)                                                            |                    | + `is_signed_b_i[0:15]`, + `zero_i[0:15]`; input reg → 8 `mux_n` → hi/lo split → **16 `gate_b_n_sqr` (per-DP8)**. `ctr_l/ctr_h`, the negate path, and the carry plumbing **removed**. Gates are per-DP8 because mode 5 idles one DP8 of every pair.                                                                                                                                                                                                         |
| **`ctrl` (square)**                                                                                                 |                    | route `is_signed_a/b[16]` to the dispatchers; emit `zero_i[16]` (idle set = today's `CTR==ZERO`); **drop** the B-negate codes (mode 12 stays SW-pre-negated); add the **6-bit `neg`** for `pe_array_sqr` (mode 10 = `6'b110011`, mode 11 = `6'b001111`, else 0); LUT: mode-5 `is_signed_b` idle DP8s → 1.                                                                                                                                                   |
| **`pe_array_sqr.sv`**                                                                                               | **built — Gate 3** | 16× `dp_8_sqr` + the same crossed 4-level CPR tree, with **6× [comp_n](../../../rtl/comp_n.sv)** one's-complementing the **lo** legs of L0 nodes 0–5 before `ext_n` (the relocated modes-10/11 negate; `neg[5:0]`). L0 hi `shift_n` runs **unsigned** (hi DP8s never negated); rest signed. Widths: node **18/26/30/38/39**, tap **19/30/38/39** (L3 `EXT=1`). **No idle logic** (dispatcher's job, §3). See [the built tree](#pe_array_sqr--built-gate-3). |
| **`pe_array_alpha_sqr` / `pe_array_beta_sqr`** (+ `dp_8_alpha_sqr`/`dp_8_beta_sqr`, `gate_n_sqr`/`gate_n_beta_sqr`) | **built**          | α (per-row) / β (per-column) generators — `pe_array_sqr` with one operand removed and the DP8 swapped, same tree/widths/taps and the same 6-bit `neg` (§4). The removed operand's `−8` is injected in the generator by `gate_n_sqr` (flag-selected, `4→5` bit) / `gate_n_beta_sqr` (fixed `−8` + idle-zero). See [Alpha/beta generators — built](#alphabeta-generators--built). Grid fan-out (8 α + 8 β) is the `top_NxN_sqr` gate.                         |
| **`const_sqr.sv`**                                                                                                  | **built**          | the per-mode `C` LUT (4-bit mode → `C`). Fully additive accounting: `c_o = C_real + 4` (Im/real outputs), signed `c_neg_o = 4 − 2N` (negated Re outputs, `2N = 34/68` for modes 10/11). Folds the centering `C_real` (§3), the α/β-complement `+4` (every output), and the block-negate `−2N` (Re only). See [Constant C — const_sqr](#the-constant-c--const_sqr).                                                                                          |
| **`acc_array_sqr.sv`** (variant)                                                                                    | LATER              | fully **additive** — sum the carry-save taps `PE + (−α) + (−β) + C` (generators emit `−α`/`−β`; `C` from `const_sqr`), no subtractor and no carry-in, then the **`÷2`** (seed `<<1` on load / readout `>>1` so `acc_i`/`out_q` stay native). The old "correction CPR row + subtract" scheme is replaced by this all-adder resolve.                                                                                                                          |
| **`top_NxN_sqr.sv`** (variant)                                                                                      | LATER              | the **bordered grid** (N² `pe_sqr` + N α + N β generators) + the `C` LUT.                                                                                                                                                                                                                                                                                                                                                                                   |
| **`C` LUT**                                                                                                         |                    | per-mode constant from §3 (signs pre-folded; `C(Re)=0`). No runtime sign logic.                                                                                                                                                                                                                                                                                                                                                                             |

### The negation relocation (summary)
- REMOVE: `b^im` two's-complement negate in `disp_array_b`/`gate_b_n` (int8 negate + L→H carry chain). SAVES that; `gate_b_n_sqr` becomes centering + zero only.
- ADD: a carry-save one's-complement (`comp_n`) on the lo legs of L0 nodes 0–5 in `pe_array_sqr` (modes 10/11), and the same 6-bit `neg` in the α/β generator reductions.
- Control is free (re-derive the 6-bit `neg` from the existing complex-sign LUT). Mode 12 is untouched (SW pre-negation). The squarer stays add-only; α/β stay shared.

### `pe_array_sqr` — built (Gate 3)

The square PE array is the baseline [pe_array](../../../rtl/pe_array.sv) tree with two local changes; everything else (crossed L0 pairing `CX0=4·(n/2)+n%2`, `CX1=CX0+2`; the shift/extend/compress node; the single L0 register; the tap-per-level slicing) is unchanged.

**1 — the leaves.** 16× `dp_8_sqr` replace `dp_8`. Each emits an **18-bit unsigned** square-sum `S_DP8` (16 value + 2 guard); operands arrive pre-centered, so `is_signed_a/b` are gone.

**2 — the negate (modes 10/11).** One `comp_n` (`WIDTH=18, SIZE=2`) sits on the **lo** (`CX1`) carry-save pair of each L0 node 0–5, **before** its `ext_n`, driven by `neg[n]`:

```
neg[n]=1  →  (lo_sum, lo_carry) = (~S_sum, ~S_carry)   resolves to  −S_DP8 − 2
```

The tree sign-extends `~S_DP8` to `−S_DP8−1` per row; the leftover **`+2` per negated block** is data-independent and rides into `acc_array_sqr`'s `C` (a `+2·weight` per negated block, on top of the centering `C` of §3). Nodes 6/7 have no `comp_n` — their DP8s are never negated — so `neg` is **6 bits**, indexed by L0 node. Negated DP8s = {2,3,6,7,10,11}; `neg`: mode 10 = `110011`, mode 11 = `001111`, else 0.

**Signedness.** Everything is signed **except the L0 `shift_n`**: it acts on the hi (`CX0`) leg, which is never negated, so `S_DP8 ≥ 0` there and sign-extend = zero-extend → it runs `IS_SIGNED=0` (unsigned). The lo `ext_n` (post-`comp_n`) and every compressor/shift from L0's CPR onward run signed.

**Widths.** A square-sum has no cancellation, so it fills all 16 value bits — one bit more than the baseline dot product — and `dp_8_sqr` is 18-bit (2 guard) vs the baseline's 20-bit (4 guard). The 2 guard bits ride L0–L2 with `EXT=0`; **L3 merges the two halves with no shift** (its value doubles without a shift adding width), so it takes `L3_EXT=1` to hold the margin:

| level | baseline node / tap | **square node / tap** |
| ----- | ------------------- | --------------------- |
| DP8   | 20 / —              | **18** / —            |
| L0    | 28 / 18             | **26 / 19**           |
| L1    | 32 / 29             | **30 / 30**           |
| L2    | 40 / 37             | **38 / 38**           |
| L3    | 40 / 38             | **39 / 39**           |

The widest value is mode 8 (R16R16) at L3 (≈2³⁶·¹⁹ → 37-bit) inside the 39-bit node/tap. Unlike the baseline, the square value nearly fills each node, so at L1/L2/L3 **tap = node** (no wider pass-through to strip); only L0 truncates the mode-8 pass-through it never reads. `tap = widest-reading-mode value + 2 guard`.

**Verified** ([tb_pe_array_sqr](../../../tb/tb_pe_array_sqr.sv), Gate 3): driven through the real square dispatchers, golden = per-DP8 `S_DP8` → block negate (`−S_DP8−2`) → crossed weighted tree, checked at each mode's read-level tap. All 11 modes × 200 corner-biased vectors (incl. negate 10/11, idle-zero 5/6, widest mode 8), 0 mismatches, `-Wall` clean. RTL confirmed against [pe_array_sqr.excalidraw](../../diagrams/pe_array_sqr.excalidraw).

### Alpha/beta generators — built

The α (per-row) and β (per-column) correction generators are [pe_array_alpha_sqr](../../../rtl/pe_array_alpha_sqr.sv) / [pe_array_beta_sqr](../../../rtl/pe_array_beta_sqr.sv): each is `pe_array_sqr` with **one operand removed** and the 16 DP8 cores swapped, so the tree, the 6× `comp_n` block-negate, the widths (18/26/30/38/39) and taps (19/30/38/39) are **byte-identical** to the PE. This is required — α, β and PE must pass through the *same* linear `L(·)` for `Result = ½(PE − α − β + C)` to hold — and it means α/β widths never grow differently (every square, PE/α/β, is bounded by `[0,256]`).

**The generator DP8s** inject the *removed* operand's `−8` in place of the PE's per-lane operand add. The dispatcher already centered the live nibble to `[−8,7]` (one `−8`); the generator adds at most **one more** `−8` (the removed operand's) — it never builds `−16` (that is dispatcher `−8` + generator `−8`; two generator `−8`s would overflow 5 bits). Two tiny gates do it:

- `gate_n_sqr` — `is_signed ? {n3,n} : {1,~n3,n[2:0]}` = sign-extend or `−8`, `4→5` bit. Used by `dp_8_alpha_sqr` (both blocks, `is_signed_b`) and `dp_8_beta_sqr`'s high block (`is_signed_a`).
- `gate_n_beta_sqr` — `zero ? 0 : {1,~n3,n[2:0]}` = fixed `−8` with idle-zero. Used by `dp_8_beta_sqr`'s low block (A-low is structurally unsigned → fixed `−8`; its `zero_i` kills the idle `(−8)²=64` leak that the flag-driven gates avoid via `is_signed=1`).

So `dp_8_alpha_sqr = Σ 16·(AH−8·bu)² + (AL−8·bu)²` (one `bu` both blocks) and `dp_8_beta_sqr = Σ 16·(B−8·au)² + (B−8)²` (`au` on the high block, fixed on the low). β keeps the AH/AL block split because each `b` compensates the b²-term of *both* products (`AH·b`, `AL·b`).

**Emit `−α` / `−β`** (fully-additive accumulator): the generators **one's-complement every output tap** (`~tap = −tap − 2`), so the accumulator *adds* the correction (`PE + (−α) + (−β) + C`) — no subtractor, no carry-in. The complement is amortized: done once in each of the 16 shared generators, not in the 64 per-PE accumulators. The deferred `−2` per operand (α, β) is a constant `+4` folded into `C`; the 6 block-`comp_n` are untouched (they set the complex σ sign inside the tree, and the output `~` negates the whole correctly-signed result). The resulting `C` LUT is [const_sqr](../../../rtl/const_sqr.sv) (the `acc_array_sqr` row in §7).

**Verified** ([tb_pe_array_alpha_sqr](../../../tb/tb_pe_array_alpha_sqr.sv) / [tb_pe_array_beta_sqr](../../../tb/tb_pe_array_beta_sqr.sv)): driven through the real dispatchers, golden = per-DP8 α/β square-sum with the exact gate bias → block negate (`−val−2`) → crossed weighted tree, at each read-level tap (now compared against `−(tree)−2`, since the arrays emit `−α`/`−β`). All 11 modes × 200 corner-biased (incl. idle 5/6 with the β-AL leak fix, negate 10/11, widest mode 8), 0 mismatches, `-Wall` clean. RTL confirmed against the `dp_8_{alpha,beta}_sqr` / `pe_array_{alpha,beta}_sqr` diagrams (which now draw the `G`/`G Beta` gates + `~IS_SIGNED_*`/`ZERO` controls).

### The constant C — const_sqr

Because the generators emit `−α`/`−β` and the block negate is `comp_n`-deferred, the accumulator resolve is a pure **carry-save add** of four terms — `PE + (−α) + (−β) + C` — then `÷2`. No subtractor, no carry-in: every `+1`/`+2` correction is data-independent and lives in the one per-mode constant `C`, held by [const_sqr](../../../rtl/const_sqr.sv) (a 4-bit-mode LUT). `C` folds three pieces:

- `+ C_real` — the excess-8 **centering** constant (§3). Real modes and the **Im** half of complex modes; `Re`'s `C_real = 0` (the `+re·re` / `−im·im` centering constants cancel).
- `+ 4` — subtracting α and β via one's-complement defers `−2` each → `+4` on **every** output.
- `− 2N` — the block-negate deferral (§4), tree-weighted, on the **negated Re** outputs only (modes 10/11; `2N = 34`, `68`).

So `const_sqr` emits two signed constants the accumulator **adds**:

| C on                   | value      | 1    | 2     | 3       | 5    | 6     | 7       | 8          | 9          | 10    | 11    | 12         |
| ---------------------- | ---------- | ---- | ----- | ------- | ---- | ----- | ------- | ---------- | ---------- | ----- | ----- | ---------- |
| positive / Im (`c_o`)  | `C_real+4` | 1028 | 36868 | 4892676 | 2052 | 73732 | 9785348 | 2595360772 | 1297680388 | 36868 | 73732 | 1297680388 |
| negated Re (`c_neg_o`) | `4−2N`     | —    | —     | —       | —    | —     | —       | —          | —          | −30   | −64   | +4         |

(`c_neg_o` only applies to the Re outputs of the complex modes; mode 12 is SW-pre-negated so `2N = 0` → `+4`.)

---

## 8. Amortization & area/power expectation

- α shared per **row**, β per **column** → **8 α + 8 β** generators for a 64-PE grid, while the multiply→square saving is paid back in all 64 PEs.
- First-order (±50%, synthesis is the arbiter): DP8 core area ≈ −15…−25%, power ≈ −20…−30%; whole PE area ≈ −7…−13%, power ≈ −10…−16%; full grid net area ≈ −5…−7%, net power ≈ −10…−12% after α/β overhead (~1–3%).
- The whole bet: `2×(5-bit square + 5-bit adder) < 1× int8×int4 Booth multiply` per lane — **must be measured** (plan Gate 5).

---

## 9. Verification (established)

- **Math, all 11 modes**: `½(PE − α − β + C) == Σ a·b` (real) and `== Re/Im(D)` (complex), over random + corner-biased inputs; every square argument ∈ `[−16,14]`. (Independent block-model checker + per-mode checkers all pass.)
- **Per-mode `C`** cross-checked independently (§3 table).
- **`dp_8_sqr`** (Gate 1): `sum_o + carry_o == Σ 16·(AH+b)²+(AL+b)²` over corner-biased signed nibbles + all 8 extreme combos — passes, `-Wall` clean.
- **Dispatchers** (Gate 2): [tb_disp_array_sqr] models on `tb_disp_array` — a golden router that **routes** (block select), **centers** (`center_a`/`center_b` per `is_signed`), and **zeros** idle DP8s (`zero_i`), checked against every `a_dp8_o`/`b_dp8_o` across all 11 modes × (random + ramp).
- **`pe_array_sqr`** (Gate 3): `tb_pe_array_sqr` drives the DUT **through** the square dispatchers; golden = per-DP8 `S_DP8` → block negate (a negated block resolves to `−S_DP8−2`) → crossed 4-level weighted tree, compared at each mode's read-level tap. All 11 modes × 200 corner-biased vectors (negate 10/11, idle-zero 5/6, widest mode 8 at L3), 0 mismatches, `-Wall` clean; widths 18/26/30/38/39 (tap 19/30/38/39) confirmed sign-consistent.
- **α/β generators**: `tb_pe_array_alpha_sqr` / `tb_pe_array_beta_sqr` drive `pe_array_alpha_sqr` / `pe_array_beta_sqr` **through** the A/B dispatchers; golden = per-DP8 α/β square-sum with the gate bias (α: `−8·bu` both blocks; β: `−8·au` high, fixed `−8`/idle-`0` low) → block negate → crossed tree, at each read-level tap. All 11 modes × 200 corner-biased (incl. the β-AL idle leak fix), 0 mismatches, `-Wall` clean; same widths/taps as `pe_array_sqr`.
- Equivalence oracle for the full path: **bit-exact match to `top_NxN`** for identical inputs, all modes, single-shot + accumulation, corner-biased extremes. Golden = the existing per-mode matmul model, extended to compute α/β and the `S`/÷2 path.
- Sign-consistency rule (carry-save): the *reduction tree* outputs must be sign-consistent (never `EXT=0` on a sign-extended multi-row CPR); note `dp_8_sqr`'s own square-sum is unsigned/non-negative and carries no such contract.

## 10. Staged build (`_sqr`)

1. ✅ **`s_5_bit_sqr`, `dp_8_sqr` + `tb_dp_8_sqr`** (Gate 1) — the square-sum primitive, checked `sum+carry == golden` on pre-centered signed nibbles.
2. ✅ **`gate_a_n_sqr`, `gate_b_n_sqr`, `disp_array_a_sqr`, `disp_array_b_sqr` + `tb_disp_array_sqr`** (Gate 2) — centering + idle-zero; golden route/center/zero model.
3. ✅ **`pe_array_sqr` (+ `comp_n`) + `tb_pe_array_sqr`** (Gate 3) — 16× `dp_8_sqr` + 6× `comp_n` block-negate on L0 nodes 0–5 (modes 10/11); widths sized (18/26/30/38/39, tap 19/30/38/39, L3 `EXT=1`) and sign-checked through the dispatchers.
4. ✅ **α/β generators** (`pe_array_alpha_sqr`/`pe_array_beta_sqr` + `dp_8_alpha_sqr`/`dp_8_beta_sqr` + `gate_n_sqr`/`gate_n_beta_sqr`) — per-DP8 α/β square-sums through the same tree, verified per-tap through the dispatchers.
5. **`acc_array_sqr`** (current) — correction row (`−α−β`) + `C` (per-mode centering constant **+ `2·weight` per negated block**, §4) + ÷2 (seed`<<1`/readout`>>1`).
6. **`top_NxN_sqr` grid** — bordered grid (N² `pe_sqr` + N α + N β generators + `C` LUT); re-verify `== top_NxN`.
7. **Payoff** — synthesize `top_NxN` vs `top_NxN_sqr`, compare area/power.

---

## 11. Open items / risks

- Area win unproven — hinges on `2×(5-bit square+adder) < 1× Booth mult`; Gate 5 (synthesis) decides.
- ~~Exact tree width growth in `pe_array_sqr`~~ — **resolved** (Gate 3): node 18/26/30/38/39, tap 19/30/38/39, L3 `EXT=1`; mode-8 headroom confirmed by tb.
- Squarer implementation — `s_5_bit_sqr` is a flat K-map gate cloud; LUT/ROM vs folded PP array affects the win (revisit at synthesis).
- ~~Complex `neg` relocation cost~~ — **resolved** (Gate 3): 6× `comp_n` one's-complement on the L0 lo legs, no carry injected (the `+2`/block is deferred to `acc_array_sqr`'s `C`); fits the existing CPR headroom.
- α/β generator **cost** & row/col fan-out — the generators are built and bit-exact, but whether `8 α + 8 β` stay small enough to preserve amortization is a **synthesis** question (the generators reuse the whole `pe_array_sqr` tree; the payoff gate measures it).

## 12. References
- General math + hardware bit-level: [square_basics.tex](./square_basics.tex)
- Per-mode centered sheets: `mode_1_opt`…`mode_12_opt` (`.tex`/`.pdf`/`.md`) in this folder.
- Baseline RTL: [ctrl.sv](../../../rtl/ctrl.sv), [disp_array_a.sv](../../../rtl/disp_array_a.sv), [disp_array_b.sv](../../../rtl/disp_array_b.sv), [gate_b_n.sv](../../../rtl/gate_b_n.sv), [dp_8.sv](../../../rtl/dp_8.sv), [pe_array.sv](../../../rtl/pe_array.sv), [acc_array.sv](../../../rtl/acc_array.sv).
- Square RTL (built): [s_5_bit_sqr.sv](../../../rtl/s_5_bit_sqr.sv), [dp_8_sqr.sv](../../../rtl/dp_8_sqr.sv), [gate_a_n_sqr.sv](../../../rtl/gate_a_n_sqr.sv), [gate_b_n_sqr.sv](../../../rtl/gate_b_n_sqr.sv), [disp_array_a_sqr.sv](../../../rtl/disp_array_a_sqr.sv), [disp_array_b_sqr.sv](../../../rtl/disp_array_b_sqr.sv), [comp_n.sv](../../../rtl/comp_n.sv), [pe_array_sqr.sv](../../../rtl/pe_array_sqr.sv), [gate_n_sqr.sv](../../../rtl/gate_n_sqr.sv), [gate_n_beta_sqr.sv](../../../rtl/gate_n_beta_sqr.sv), [dp_8_alpha_sqr.sv](../../../rtl/dp_8_alpha_sqr.sv), [dp_8_beta_sqr.sv](../../../rtl/dp_8_beta_sqr.sv), [pe_array_alpha_sqr.sv](../../../rtl/pe_array_alpha_sqr.sv), [pe_array_beta_sqr.sv](../../../rtl/pe_array_beta_sqr.sv), [const_sqr.sv](../../../rtl/const_sqr.sv).
- Staged build plan: `.claude/plans/` (`_sq` plan).
