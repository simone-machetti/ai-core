# Square variant — implementation reference

Design/implementation notes for the **square** variant of the reconfigurable MatMul PE: replace the per-lane **multiply** inside each `DP8` with an **add-then-square** on centered 4-bit nibbles, and compensate outside the squarer with per-row `α`, per-column `β`, and a per-mode constant `C`. External behaviour of the PE and the N×N grid is unchanged.

This file is the single place to look when implementing. Companion material in the same folder: the general math in [square_basics.tex](./square_basics.tex), the per-mode formula sheets [mode_N_opt.tex](./mode_1_opt.tex)/`.pdf` and notes `mode_N_opt.md`. Staged build plan: the `_sq` plan in `.claude/plans/`.

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
Split each int8 `a = 2⁴·a_H + a_L`, turning the 8×4 multiply into two 4×4 products, each done as an add-then-square on ~5-bit operands. The squarer is a **5-bit-in / 9-bit-out** unit — the whole area/power bet is that `2×(5-bit square + 5-bit adder) < 1× int8×int4 Booth multiply` per lane (to be settled by synthesis).

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

| u | (x,y) | S | formula | PE | α=(x−S)² | β=(y−S)² | C/lane |
|---|---|---|---|---|---|---|---|
| 0 | s,s | 0 | (1) | `(x+y)²` | `x²` (4b) | `y²` (4b) | 0 |
| 1 | u,s | 8 | (3) | `((x−8)+y)²` | `(x−8)²` | `(y−8)²` | 64 |
| 1 | s,u | 8 | (3) | `(x+(y−8))²` | `(x−8)²` | `(y−8)²` | 64 |
| 2 | u,u | 16 | (5) | `((x−8)+(y−8))²` | `(x−16)²` | `(y−16)²` | 256 |

Rows `u=1` (`u,s` vs `s,u`): α and β are both `x−8`/`y−8`, but the widths swap (the signed operand's `−8` lands in `[−16,−1]` = 5b; the unsigned operand's `−8` lands in `[−8,7]` = 4b). The 5-bit unit covers both.

The `−8` on a signed operand's α/β (e.g. `(y−8)²` when y is signed) is the **removed operand's biased zero**: `α = PE(x,0)`, `β = PE(0,y)`, and zeroing an *unsigned* operand still centers it to `−8`.

---

## 3. Signedness rule and per-mode mapping

**Rule**: for each independent operand, ONLY its single most-significant nibble is SIGNED (δ=0); every lower nibble is UNSIGNED (δ=8, biased −8).
- int4 operand: its one nibble is signed.
- int8 `X` → `X_H` (signed), `X_L` (unsigned).
- int16 `X` → `X_H^hi` (signed), `X_L^hi, X_H^lo, X_L^lo` (unsigned).
- complex: `a^re, a^im, b^re, b^im` are each independent operands (top nibble signed, rest unsigned).

This matches the datapath's per-slice signedness (`pe_ctrl` `IS_SIGNED_A_LUT`/`IS_SIGNED_B_LUT`, MSB slice signed) and is what keeps every square in 5-bit. Correctness of `½(PE−α−β+C)=Result` holds for *any* centering; the signedness choice only governs the bit-width.

### Per-mode constant `C` (verified)

| mode | kind | operands | `C` |
|---|---|---|---|
| 1 | real | int8×int4 (16 lanes) | 1 024 |
| 2 | real | int8×int8 (16) | 36 864 |
| 3 | real | int16×int8 (8) | 4 892 672 |
| 5 | real | int8×int4 (32) | 2 048 |
| 6 | real | int8×int8 (32) | 73 728 |
| 7 | real | int16×int8 (16) | 9 785 344 |
| 8 | real | int16×int16 (16) | 2 595 360 768 |
| 9 | real | int16×int16 (8) | 1 297 680 384 |
| 10 | complex | C8×C8 (8) | Re 0 · Im 36 864 |
| 11 | complex | C8×C8 (16) | Re 0 · Im 73 728 |
| 12 | complex | C16×C16 (4) | Re 0 · Im 1 297 680 384 |

`C` is data-independent → precompute per mode (a small LUT / constant) and inject once at the accumulator. Block constant = `weight × Nlanes × S²`; `Nlanes` is 8 per DP8(4×4) **except mode 12** (`C-DP4`, `Nlanes = 4`, so block const uses `4·S²`).

### Zero-gating (modes 5/6, idle lanes)
A zeroed unsigned lane still nets to 0: `½((y−8)² − 64 − (y−8)² + 64) = 0`. Idle lanes are automatically consistent — no special handling needed in the square math. (Gating is the B-gate `ZERO` code, see §6.)

---

## 4. Complex negation — the key finding

Complex modes (10/11/12) have negated products, e.g. `Re(D) = Σ a^re·b^re − Σ a^im·b^im`.

**Uncentered**, negation is free via *subtract-and-square*: `−x·y = ½[(x−y)² − x² − y²]`, with α=x², β=y² unchanged (sign-blind, since `(−y)²=y²`). The baseline formula sheets and the baseline multiply datapath both rely on this.

**Under centering this breaks.** α/β carry a *directional* `−8` that cancels a specific linear term; flipping the product sign flips the sign of the linear term needed, but the shared α/β still cancel the old sign → they double it → a **data-dependent leftover** `4δx·y + 4δy·x`, which cannot be a constant `C`. (Verified: the required "constant" scatters over `{…,−160,…,32,…}`.)

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

---

## 5. Bit-level hardware for centering

The bias is one primitive: **flip the nibble MSB** (the weight-8 bit) → `−8`, converting unsigned→signed. One XOR per nibble MSB, gated by `~is_signed`. There is **no separate `−16`** operation.

### Where each piece lives

| logic | what | where | shared? |
|---|---|---|---|
| `−8` MSB-flip (centering → `x_c, y_c`) | flip nibble MSB iff unsigned | **dispatcher output** | per row (a), per column (b) — identical for PE and α/β, so do it once |
| α/β `−S` completion (the `−16` bit) | removed operand's extra `−8` | **α/β generator input** | per generator (2 gates) |
| add + 5-bit square | — | PE / α / β cores (identical) | — |
| constant `C` | per-mode | acc-array injection | grid-wide (one per mode) |

### α/β generator remap (optimized, other operand removed)
The `−16` is never a real `−16`: it is two `−8`s summed. In the optimized generator (the removed operand's path is gone, so there is no adder to add the second `−8`), apply the total bias `S` to the top two bits of the live operand (β shown; α is symmetric with the removed-operand flag as the OR term). `au = ~is_signed_a`, `bu = ~is_signed_b`:

```
β_arg[2:0] = y[2:0]                       (pass through)
β_arg[3]   = y[3] XOR au XOR bu
β_arg[4]   = au OR (y[3] XOR bu)
```

Truth table (β; `y3 = y[3]`):

| au bu | S | β_arg[4] β_arg[3] | value |
|---|---|---|---|
| 0 0 | 0 | `y3 y3` | `y` (sign-extended) |
| 0 1 | 8 | `~y3 ~y3` | `y−8` (y unsigned = MSB-flip) |
| 1 0 | 8 | `1 ~y3` | `y−8` (y signed) |
| 1 1 | 16 | `1 y3` | `y−16` (y unsigned = set bit 4) |

So the `−16` case (both unsigned) is literally "set bit 4" (prepend a `1` to the raw unsigned nibble). Two gates on the top bits; low 3 bits pass through. No adder needed.

**Formula-3 sanity (row `1 0`, x unsigned / y signed):** the PE sees `y` normal (`y_c = y`, no flip because y is signed); β sees `y−8`. The `−8` in β is the removed x's biased zero, applied only in the β generator — this is why the centering `−8` is shared at the dispatcher while the `−S` completion stays inside α/β.

---

## 6. Baseline RTL — what exists today (read before changing)

Files in [rtl/](../../../rtl/). Relevant structure:

- **`disp_array.sv` + `gate_b_n.sv`** — routes/gates the B operand. `gate_b_n` codes (2-bit `sel`): `00` pass, `01` zero (idle lanes), `10` `GATE_NEG`, `11` `GATE_NEG_CARRY`. Negating an int8 B negates its two int4 nibbles across two halves: low nibble `GATE_NEG`, high nibble `GATE_NEG_CARRY` (carry chained low→high) for an exact full-width two's-complement.
- **`pe_ctrl.sv`** — per-mode LUTs. `CTR_L_LUT`/`CTR_H_LUT` drive the B-gate codes: `2'd1` (zero) appears on the idle-lane modes; `2'd2`/`2'd3` (NEG / NEG_CARRY) appear on the **complex** entries' imaginary pairs → **the complex minus is done by negating `b^im`**. `IS_SIGNED_A_LUT`/`IS_SIGNED_B_LUT` give per-DP8 signedness (MSB slice signed).
- **`dp_8.sv`** — the primitive being replaced. Ports: `a_i[8×int8]`, `b_i[8×int4]`, `is_signed_a_i`, `is_signed_b_i`, → 20-bit carry-save `sum_o`/`carry_o` (16-bit value + 4 guard, sign-consistent).
- **`pe_array.sv`** — instantiates 16 `dp_8` and reduces their carry-save outputs through a **purely additive** 4-level CPR-4:2 tree (`node = prev + shift`, shifts 8/4/8/– at L0..L3, all `IS_SIGNED=1` = sign-extension only). Node widths 28/32/40/40; carry-save taps 18/29/37/38 exported at every level. **No subtract, no per-block sign anywhere in the tree.** L0 is registered.
- **`acc_array.sv`** — resolves/accumulates the tap; folds a 3rd CPR row via the `acc_i`/`sel_acc` mux (seed OR feedback, exclusive).
- **`pe_datapath.sv` / `top_pe_bas.sv` / `top_NxN_bas.sv`** — datapath, single-PE top, grid.

**Key takeaway:** today the complex sign is *entirely operand negation* in `disp_array`; the tree only adds. That is exactly the *subtract-and-square* path that centering forbids (§4).

---

## 7. Required changes, module by module

| module | change |
|---|---|
| **`dp_8_sq.sv`** (NEW, drop-in for `dp_8`) | split each `a` into nibbles, MSB-flip unsigned nibbles (or receive already-centered operands from the dispatcher), form `(a_H+b)`/`(a_L+b)` with 5-bit adders, 5-bit-in/9-bit-out squares, weight the `a_H` square by 2⁴, sum 16 squares → `S_DP8` (raw square-sum, **no α/β inside**). Same ports as `dp_8` + no extra inputs. Output ≈ 21-bit carry-save (`S_DP8 ≈ 2¹⁶`, ~+1 bit vs baseline). Reuse `add_n`, `cpr_w_n`/`fa`, `ext_n`/`shift_n`. |
| **centering** | one XOR per nibble MSB, gated by `~is_signed`, at the **dispatcher output** (shared per row/col by PE and the α/β generators). See §5. |
| **`disp_array` / `gate_b_n`** | **remove** the complex B-negate path (`GATE_NEG`/`GATE_NEG_CARRY` for imaginary pairs). You no longer negate `b^im`. Keep `ZERO` (idle-lane) gating. |
| **`pe_array`** (→ PE) | **add** a conditional carry-save negate on each of the 16 DP8 outputs before L0: `−(sum,carry) = (~sum, ~carry) + 2` (XOR both 20/21-bit words with a per-DP8 `neg` bit + inject the two `+1`s as CPR carry-ins). This is the relocated complex sign. Otherwise structurally unchanged; allow **+1–2 bit** width bump and re-check mode-8 (widest) headroom. |
| **`neg` control** | derive a per-DP8 `neg` bit from the existing complex-sign info (the `CTR_*`/mode LUT that today selects `GATE_NEG`). Dynamic per Re/Im cycle, same timing as today's B-negate. |
| **α-gen / β-gen** (NEW, periphery) | 8 α-units (per row) + 8 β-units (per column). Each: the `−S` top-bit remap (§5) + 5-bit square + a copy of the mode-weighted **signed** reduction (same weights AND the same per-block `neg` as `pe_array`) → `A_corr[r]` / `B_corr[c]`, fanned into every PE in that row/column. Mode is grid-uniform. |
| **`acc_array_sq.sv`** (variant) | inject `−(A_corr + B_corr)` per output lane (a dedicated correction CPR row so it coexists with running-accumulate; keep `EXT=2`/`CARRY=2`), add the constant `C` (per-mode LUT; `0` for Re of complex modes), and the **`÷2`** (right-shift-1 at output). Run the accumulator in 2× units: **seed `<<1` on load, readout `>>1`** so `acc_i`/`out_q` stay native and external behaviour is identical. |
| **`top_pe_sq.sv`** (variant) | instantiate the `_sq` datapath; pipeline the per-cycle α/β/correction inputs to the acc stage (α/β are **per-operand-presentation** inputs — they change each accumulation iteration with the operands — not the one-time seed). |
| **`top_NxN_sq.sv`** (variant, LATER) | the grid + the 8 α / 8 β generators at the periphery. |
| **`C` LUT** | per-mode constant from §3 (signs pre-folded; `C(Re)=0`). No runtime sign logic. |

### The negation relocation (summary)
- REMOVE: `b^im` two's-complement negate in `disp_array` (int8 negate + L→H carry chain). SAVES that.
- ADD: conditional carry-save negate of the 16 DP8 outputs at `pe_array` L0 inputs, and the same per-block `neg` in the α/β generator reductions.
- Control is free (re-derive `neg` from the existing complex-sign LUT). Net: a modest, bounded increase (negating a ~21-bit CS pair vs an 8-bit operand), partly offset by dropping the operand negator. The squarer stays add-only; α/β stay shared.

---

## 8. Amortization & area/power expectation

- α shared per **row**, β per **column** → **8 α + 8 β** generators for a 64-PE grid, while the multiply→square saving is paid back in all 64 PEs.
- First-order (±50%, synthesis is the arbiter): DP8 core area ≈ −15…−25%, power ≈ −20…−30%; whole PE area ≈ −7…−13%, power ≈ −10…−16%; full grid net area ≈ −5…−7%, net power ≈ −10…−12% after α/β overhead (~1–3%).
- The whole bet: `2×(5-bit square + 5-bit adder) < 1× int8×int4 Booth multiply` per lane — **must be measured** (plan Gate 5).

---

## 9. Verification (established)

- **Math, all 11 modes**: `½(PE − α − β + C) == Σ a·b` (real) and `== Re/Im(D)` (complex), over random + corner-biased inputs; every square argument ∈ `[−16,14]`. (Independent block-model checker + per-mode checkers all pass.)
- **Per-mode `C`** cross-checked independently (§3 table).
- Equivalence oracle for RTL: **bit-exact match to `top_pe_bas`** for identical inputs, all modes, single-shot + accumulation, corner-biased extremes (to catch sign-consistency at the square-sum boundary). Golden = the existing per-mode matmul model used by `tb_top_pe_bas`, extended to compute α/β and the `S`/÷2 path.
- Sign-consistency rule (carry-save): outputs must be sign-consistent (never `EXT=0` on a sign-extended multi-row CPR); test with corner-biased extremes.

## 10. Staged build (from the `_sq` plan)

1. `dp_8_sq` + `tb_dp_8_sq` — check `S_DP8` == golden square-sum AND `½(S_DP8 − α_tb − β_tb) == dp_8(a,b)` (α/β in the tb). Proves the compensation math at DP8 level with no α/β hardware.
2. `acc_array_sq` — correction row + ÷2 + seed`<<1`/readout`>>1`.
3. `pe_datapath_sq` + `top_pe_sq` — α/β/correction as tb input ports; prove `== top_pe_bas` across all modes, single-shot + accumulating. Add the per-DP8 `neg` for complex.
4. α/β generator RTL + `top_NxN_sq` grid — 8 α / 8 β periphery; re-verify grid equivalence.
5. Payoff — synthesize `top_NxN_bas` vs `top_NxN_sq`, compare area/power.

---

## 11. Open items / risks

- Area win unproven — hinges on `2×(5-bit square+adder) < 1× Booth mult`; Gate 5 decides.
- Exact tree width growth (+1–2 bit) — size precisely; confirm mode-8 headroom.
- Squarer implementation — LUT/ROM vs folded PP array; affects the win.
- Complex `neg` relocation cost (§7) — confirm the CS-negate + carry injection fits the existing CPR headroom (`pe_array` runs `EXT=0`).
- α/β generator cost & row/col fan-out — must stay small to preserve amortization.

## 12. References
- General math + hardware bit-level: [square_basics.tex](./square_basics.tex)
- Per-mode centered sheets: `mode_1_opt`…`mode_12_opt` (`.tex`/`.pdf`/`.md`) in this folder.
- Baseline RTL: [pe_array.sv](../../../rtl/pe_array.sv), [disp_array.sv](../../../rtl/disp_array.sv), [gate_b_n.sv](../../../rtl/gate_b_n.sv), [pe_ctrl.sv](../../../rtl/pe_ctrl.sv), [dp_8.sv](../../../rtl/dp_8.sv), [acc_array.sv](../../../rtl/acc_array.sv).
- Staged build plan: `.claude/plans/` (`_sq` plan).
