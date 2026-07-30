# BFP — implementation reference

Design/implementation notes for **BFP (Block Floating Point)** support in both the baseline
([top_NxN](../wiki/architectures/top_NxN.md)) and square ([top_NxN_sqr](../wiki/architectures/top_NxN_sqr.md))
architectures. This is the single place where the BFP definition lives; it grows incrementally as
decisions are made, the way [square_imp.md](formulas/square/square_imp.md) did for the square variant.

The bit-level format layouts are drawn in the **BFP** tab of [modes.xlsx](formulas/modes.xlsx)
(authoritative for exact bit positions); this file holds the semantics, the format ↔ mode mapping,
and the reasoning behind them.

**Status: formats and mode mapping converged (§1–§7); baseline BFP built and verified, square-BFP
scheme decided (§8); square-BFP build ladder in §9. Numeric policies and implementation details are open (§10).**

---

## 1. Format semantics (decided)

- **Naming**: `[R|C]BFP<W>B<N>` — Real/Complex, element storage width `W` ∈ {4, 8, 16} bits, block
  size `N` = elements sharing one exponent. For `C` formats `N` counts **complex** elements; a
  complex element occupies two rows (Re, Im), interleaved `R,i,R,i,…`.
- **Mantissas are two's complement, sign included** — an element is a plain `intW` value, so the
  existing integer datapath consumes it unchanged. Element value = `mantissa · 2^e` with `e` the
  block exponent (encoding/bias: open, §10).
- **Exponent overlap**: the shared exponent bits are stored in data bit positions that are **zero
  by construction** (LSBs of the block's first rows — exact positions per the sheet). Decode =
  extract the exponent, force those positions to 0. Containers are therefore exactly `N × W` bits.
  Rows hosting exponent bits have a coarser quantization step (data LSB always 0) — a software
  quantizer constraint, not a hardware one.
- **Exception — RBFP16B1**: block of 1, fp16-style dedicated field split `s | e[4:0] | m[9:0]`
  (11-bit two's-complement data `{s, m}`, no overlap). Exact semantics to confirm (§10).

## 2. Container catalog (dual naming, decided)

Every multi-element container has a **real** and a **complex** reading — same bits, different row
interpretation. RBFP16B2 and CBFP8B8 are pure renamings, not new layouts: RBFP16B2 is the CBFP16B1
container read as two reals; CBFP8B8 is the RBFP8B16 container read as 8 complex (3-bit element
index, rows `R,i` interleaved). The catalog is closed with zero new bit layouts.

| Container    | Real reading | Complex reading | Exp bits | Consumers                                            |
| ------------ | ------------ | --------------- | -------- | ---------------------------------------------------- |
| 64 b, 16×4   | RBFP4B16     | —               | 6        | B input — modes 1, 5                                 |
| 64 b, 8×8    | RBFP8B8      | CBFP8B4         | 6        | A/B input — modes 1, 2, 3, 5, 6, 7 (real reading)    |
| 128 b, 16×8  | RBFP8B16     | CBFP8B8         | 6        | A/B input — modes 10, 11 (complex reading)           |
| 16 b, 1×16   | RBFP16B1     | —               | 5        | X output — modes 6, 8, 9                             |
| 32 b, 2×16   | RBFP16B2     | CBFP16B1        | 5        | X output — modes 5, 7 (real); 10, 11, 12 (complex)   |
| 64 b, 4×16   | RBFP16B4     | CBFP16B2        | 7        | X output — modes 2, 3 (real reading)                 |
| 128 b, 8×16  | RBFP16B8     | CBFP16B4        | 6        | A/B input — 3, 7, 8, 9 + X output — 1 (real); A/B input — 12 (complex) |

Readings without a consumer (CBFP8B4, CBFP16B2, RBFP8B16-as-real) are spare interpretations of
containers that exist anyway — harmless, available to future modes or as memory/interchange
formats.

## 3. The three-layer model (decided)

- **Source rule (formats)** — the original matrices are BFP-blocked with one exponent per
  **64-bit source row** by default (RBFP4B16, RBFP8B8), widened to **128-bit** where the word
  packing interleaves 8 elements across chunks (int16 → RBFP16B8; C8 → CBFP8B8; C16 → CBFP16B4).
- **Transport rule (the 4 + 8)** — the 256-bit operand words carry one exponent slot per chunk:
  **4 for A** (per 64-bit block, the unit `disp_array_a` routes to a DP8) and **8 for B** (per
  32-bit half-block, the unit `disp_array_b` routes to a DP8). Packing may **cut** a source block
  across chunks; a packed 64-bit B block can then hold halves of two different source blocks (two
  exponents — why B needs 8, not 4). Every chunk maps to exactly **one** source block, so its slot
  carries that block's exponent (a copy when the block spans several chunks). Distinct exponents
  per word ≤ 4 on each side.
- **Compute rule (alignment)** — mantissas are aligned **in the datapath, at the merge points**
  where differently-scaled partials meet (post-multiply): conditional aligners at the tree's
  L0/L2/L3 merges and at the accumulator — the plan in §8. Dispatchers and DP8s are untouched:
  operands are multiplied at full stored precision and alignment discards product LSBs, not
  operand LSBs (this supersedes the earlier dispatcher pre-align idea, which was cheaper — ×2N
  instead of ×N² — but coarser). The per-output scale is
  `e_X = max(e_A over group) + max(e_B over group)` (+ output normalization, §10 policies).

## 4. Format-selection rule (decided)

**Invariant**: every chunk a DP8 consumes — 64-bit for A, 32-bit for B — must contain data from
exactly **one exponent domain** (a DP8 sums its 8 lanes immediately; its partial must have a
single scale).

1. The mode's precision class fixes the element type (int4/int8/int16, real/complex) → the
   mantissa class of the format.
2. The packing fixes the **minimum block**: the block must cover all elements with a fragment in
   the same chunk — always 8 mantissas, since a DP8 has 8 lanes:
   - *whole-element packing* (element fits the chunk): min block = 8 elements — int8 → 64 b,
     int4 → 32 b;
   - *plane packing* (element split into nibble/byte planes across chunks; each chunk holds one
     fragment of all 8 elements): min block = 8 whole elements — int16 → 128 b, C8 → 128 b
     (8 complex), C16 → 128 b (4 complex, Re/Im lanes share chunks so the complex-shared exponent
     is structural).
3. Chosen format = smallest catalog block ≥ max(min block, 64-bit source row). Only int4 sits
   above its minimum (RBFP4B16 = 16 elements by the 64-bit-row convention; the block is cut across
   two chunks, both carrying copies of its exponent).

**K never enters the format choice** — the dot-product length only decides which source blocks are
summed together, i.e. the dispatcher **alignment groups** (§6). Finer-than-minimum blocks are
impossible (a chunk would mix two domains — e.g. RBFP16B4 as an int16 input would need 8 A slots
plus sub-chunk shift deltas); and since K ≥ 8 in every mode, sub-K-group exponents would be
aligned away at dispatch without any compute benefit.

## 5. Per-mode mapping (decided)

Counts are per 256-bit operand word (inputs) and per operation (outputs). Modes 9 and 10 are
**Parallel = 2**: two independent matrix multiplications side by side (disjoint A/B block sets —
no data is replicated, and their results never merge in the tree).

| Mode | Prec — shape           | A input      | e_A | B input                          | e_B | X output     | e_X |
| ---- | ---------------------- | ------------ | --- | -------------------------------- | --- | ------------ | --- |
| 1    | R8R4 — 2×16×4          | RBFP8B8 ×4   | 4   | RBFP4B16 ×4 (cut H/L)            | 4   | RBFP16B8 ×1  | 1   |
| 2    | R8R8 — 2×16×2          | RBFP8B8 ×4   | 4   | RBFP8B8 ×4                       | 4   | RBFP16B4 ×1  | 1   |
| 3    | R16R8 — 2×8×2          | RBFP16B8 ×2  | 2   | RBFP8B8 ×2                       | 2   | RBFP16B4 ×1  | 1   |
| 5    | R8R4 — 1×32×2          | RBFP8B8 ×4   | 4   | RBFP4B16 ×4 (cut)                | 4   | RBFP16B2 ×1  | 1   |
| 6    | R8R8 — 1×32×1          | RBFP8B8 ×4   | 4   | RBFP8B8 ×4                       | 4   | RBFP16B1 ×1  | 1   |
| 7    | R16R8 — 1×16×2         | RBFP16B8 ×2  | 2   | RBFP8B8 ×4                       | 4   | RBFP16B2 ×1  | 1   |
| 8    | R16R16 — 1×16×1        | RBFP16B8 ×2  | 2   | RBFP16B8 ×2                      | 2   | RBFP16B1 ×1  | 1   |
| 9    | R16R16 — 2 ∥ (1×8×1)   | RBFP16B8 ×2  | 2   | RBFP16B8 ×2                      | 2   | RBFP16B1 ×2  | 2   |
| 10   | C8C8 — 2 ∥ (1×8×1)     | CBFP8B8 ×2   | 2   | CBFP8B8 ×2                       | 2   | CBFP16B1 ×2  | 2   |
| 11   | C8C8 — 1×16×1          | CBFP8B8 ×2   | 2   | CBFP8B8 ×2                       | 2   | CBFP16B1 ×1  | 1   |
| 12   | C16C16 — 1×4×1         | CBFP16B4 ×1  | 1   | CBFP16B4 ×1 (Re/Im arrangements) | 1   | CBFP16B1 ×1  | 1   |

Notes:

- **Mode 1 B (the cut)**: a column (16 int4 = one RBFP4B16) is cut into two 32-bit halves landing
  in the same-plane halves of two adjacent packed blocks; a packed 64-bit B block holds upper
  K-halves of two different columns (two exponents). Both chunks of one column carry copies of its
  exponent.
- **Modes 5/7 vs 9/10**: modes 5/7 share one A row across their two outputs (`SEL_A` reuses the
  same blocks — two columns of one matmul), so their two results form one X block (RBFP16B2).
  Modes 9/10 read disjoint block sets per output (two independent matmuls) — see §7.
- **Mode 12 B**: blocks {0,1} hold the operand arrangement for Re, blocks {2,3} the arrangement
  for Im — the *same* source data rearranged (with the software-pre-negated `b_im`), carrying the
  same single exponent. Mode 12 A uses blocks {0,1} only (128 b).

## 6. Alignment groups per mode (decided at concept level)

Wherever one output's K-reduction spans several source blocks, the dispatcher aligns those blocks
to their group max before the multiply. Groups by packed-block index (verified against the
`ctrl.sv` `SEL_A`/`SEL_B`/`IS_SIGNED_*` LUTs):

| Mode | A groups           | B groups                              |
| ---- | ------------------ | ------------------------------------- |
| 1    | {0,1} {2,3}        | none (a column = one source block)    |
| 2    | {0,1} {2,3}        | {0,1} {2,3}                           |
| 3    | none               | none                                  |
| 5    | {0,1,2,3}          | per column: {K0–15, K16–31} (H-plane and L-plane pairs) |
| 6    | {0,1,2,3}          | {0,1,2,3}                             |
| 7    | {0,1,2,3}          | {0,1} {2,3}                           |
| 8    | {0,1,2,3}          | {0,1,2,3}                             |
| 9    | none               | none                                  |
| 10   | none               | none                                  |
| 11   | {0,1} vs {2,3}     | {0,1} vs {2,3}                        |
| 12   | none               | none                                  |

Modes 10/12 need no alignment because the complex-shared formats (CBFP8B8/CBFP16B4) tie Re/Im by
construction and K fits one block; mode 11 aligns only across its two K-halves. For int16 and
complex operands, several chunk slots carry copies of one source exponent (byte/nibble planes,
re/im planes) — copies are always aligned by construction.

## 7. Output policy (decided)

- All results are quantized to **16-bit BFP** at the output (raw tap values are up to ~38 bits;
  normalization/rounding policy: §10).
- **One X block per matrix multiplication**: the results of one matmul share one output exponent
  (block formats RBFP16B8/B4/B2 for 8/4/2 results, RBFP16B1 for 1); the results of **independent**
  parallel matmuls (modes 9, 10) never share an exponent — each gets its own RBFP16B1/CBFP16B1.
- A complex result's Re and Im share one exponent (CBFP16B1).
- Thanks to the overlap rule, `n × B1` and one `B‑n` block cost identical storage; the block
  formats trade per-result exponents for wider mantissas (e.g. RBFP16B2: sign+15, with the
  overlapped tail LSBs forced to zero, vs RBFP16B1: sign+10).

## 8. Baseline micro-architecture plan (decided)

HW changes to support BFP on `top_NxN`. Global invariant: **the datapath keeps its integer bit
widths everywhere** — an aligned addend is a right-shifted version of its integer worst case, so
every node width, tap width and guard margin already sized for pure integer stays sufficient, and
integer modes run bit-exact through the same paths (alignment amount 0).

**Status: the baseline BFP datapath is built and verified end to end** — `sub_n_bfp`,
`shift_n_bfp`, `align_cell_bfp`, `align_bfp`, `disp_array_exp_a_bfp`, `disp_array_exp_b_bfp`,
`pe_array_bfp`, `acc_array_bfp`, `pe_bfp`, `top_NxN_bfp`, each gated on its own testbench and
integrated in `tb_top_NxN_bfp` (streaming single-shot / accumulate / scaling × equal- and
distinct-exponent, all against independent goldens). Only two new wrapper modules were needed
(`pe_bfp`, `top_NxN_bfp`); `ctrl` and the mantissa dispatchers are unchanged. Still open: the
output normalize/round/pack stage (§7), the `bfp_i`-vs-mode encoding, and a `post-syn-sta` check
of the accumulate loop.

- **`disp_array_a` / `disp_array_b` — untouched.** Alignment is post-multiply, at the merge
  points (§3 compute rule).
- **`pe_array` — conditional aligners before the CPR 4:2 of L0/L2/L3 only** (8 + 2 + 1 = 11
  sites, not 15): the L1 merge always recombines the H/L nibble halves of the *same* B block
  (same-element, same exponent), so L1 never aligns. Aligners sit after `shift_n`/`ext_n`, right
  on the width-matched CPR operands. Taps are unchanged as mantissa buses; each tap gains a
  sideband exponent (`e_node = max(e_left, e_right)` tracked through the aligned merges).
  Per-mode activation (from the §6 groups; Δ = ΔA + ΔB, ΔA row-shared, ΔB column-shared — the
  per-PE work is one small exponent add; idle-zeroed rows are scale-free):

  | Mode         | L0 (8×) | L2 (2×) | L3 (1×)     |
  | ------------ | ------- | ------- | ----------- |
  | 1            | ΔA      | –       | –           |
  | 2            | ΔA + ΔB | –       | –           |
  | 5            | ΔA      | ΔA + ΔB | –           |
  | 6            | ΔA + ΔB | ΔA + ΔB | –           |
  | 7            | –       | ΔA + ΔB | –           |
  | 8            | –       | –       | Δ(K-halves) |
  | 11           | –       | ΔK      | –           |
  | 3, 9, 10, 12 | –       | –       | –           |

- **`acc_array_bfp` — one aligner per lane, after the tap/acc muxes, before the CPR 3:2 (built,
  verified).** Each lane inserts an `align_cell_bfp` (`SIZE_0=1` acc row, `SIZE_1=2` tap
  sum/carry pair) between the accumulate mux and the CPR, bringing the accumulator row and the
  tap pair to `max(acc_exp, tap_exp)` (smaller-scale side arithmetic-right-shifted, truncating)
  before the fold. Node/guard widths are unchanged (an aligned addend is a right-shifted, smaller
  version of its integer worst case), so with all exponents equal every lane is bit-transparent
  and the array *is* `acc_array`.
  - **Exponent path**: a per-lane OUT MUX EXP (`mux_n(7,4)` on `sel_out`) picks the tap scale from
    the `pe_array_bfp` tap exponents, mirroring the data window map (L0→`[g]`, L1→`[g/2]`,
    L2→`[0/1]` on lanes 2,3,6,7, L3 on lanes 6,7; idle levels tied to the min scale 0). A per-lane
    ACC MUX EXP (`mux_n(7,2)` on `sel_acc`) picks the seed exponent `acc_exp_i` or the lane's
    registered scale. The aligner emits `max`; an exponent register per lane (loaded every cycle,
    reset to 0) holds it as the running accumulator scale and drives `pe_exp_o`.
  - **Lane fusion (`prop_carry`, even=H/odd=L)**: the pair's aligners exchange shifted-out bits
    over an **H→L fill chain** — the even lane sign-fills and feeds its three raw rows (acc, tap
    sum, tap carry), gated by `prop_carry` (the operand-isolation gate), into the odd lane, whose
    fill comes from that chain instead of sign replication; fused they form one distributed 40-bit
    three-row shifter. This runs alongside the existing L→H adder-carry chain: **one control, two
    crossing buses, opposite directions**. A fused pair receives equal exponents by construction
    (both lanes read the same tap node and, seeded consistently, hold equal registered scales), so
    the pair-shared exponent state needs no extra logic.
  - **Seed format = feedback format** (settled): the external seed and the register feedback share
    one shape — a 20-bit mantissa (40-bit split H/L over a fused pair) plus a **7-bit
    product-domain scale** (`e_A + e_B`, carrying 2×bias) — so the two accumulate muxes just
    select between same-shape operands, with **no conversion and no bias constant in the datapath**
    (bias-blind). A fresh software seed must therefore present its scale in the product domain
    (`e_format + B`); a fed-back partial sum already is. When the normalize stage lands, looping
    its output back is fine provided it stays domain-preserving (renormalize mantissa + adjust
    exponent by the shift, never strip a bias — bias-stripping is terminal-only).
  - Verified in `tb_acc_array_bfp` (full BFP chain `disp_array{,_exp}_*` → `pe_array_bfp` →
    `acc_array_bfp`, with the integer chain alongside): Pass A equal-exp bit-identical to baseline
    (single-shot + seed/feedback accumulation) with exact exponents, Pass B min-scale seed
    accumulation checked bit-exact against `(seed >>> tap_exp) + N·tap` read from the BFP tap.
  - Rejected: *align before the H/L window split* — the split is fused into the per-level
    windowing feeding the tap mux, so it means one aligner per tap level (~3–4× area, unselected
    levels toggling for nothing); *mux-then-align-then-split* — needs a separate per-lane L0 path
    (~2× shifter bits) plus a reworked front-end.
- **Output stage — normalize/round/pack** per §7 (one block per matmul), delivering the X format
  in the existing 20-bit `out_q` lanes plus a per-block output-exponent bus. May need its own
  pipeline stage (latency 3 → 4) — to settle at implementation.
- **Exponent transport — `disp_array_exp_a_bfp` / `disp_array_exp_b_bfp` (built, verified).**
  The exponent counterparts of the mantissa dispatchers, one A instance per grid row and one B
  instance per column. `pe_exp_a_i` = 4 × 6-bit (one exponent per 64-bit A block, the §3 source
  rule); `pe_exp_b_i` = 4 × 12-bit (per 64-bit B block the exponents of its two 32-bit halves:
  chunk `[11:6]` = H → even DP8, `[5:0]` = L → odd DP8, mirroring the mantissa split). Input
  registered (`reg_n`, in step with the operand registers), one `mux_n` per pair on the same
  `sel_a`/`sel_b`, then per half a `gate_n` masking the exponent to zero when its `ctr_h`/`ctr_l`
  carries the ZERO code:
  - **Both sides gate, per DP8.** Mantissa A needs no gate (a zeroed B kills the product), but
    exponents *add* — zeroing only B leaves scale = e_A (mode 6: the idle pairs 4–7 still select
    A block 0, and at the L3 merge that leftover scale can win the max and right-shift the
    *active* data). And per half, not per pair: mode 5 idles only L on pairs 0–3 and only H on
    pairs 4–7, so the two pair outputs gate independently.
  - **ZERO-decode only — never `gate_b_n` here.** NEG / NEG_CARRY must pass the exponent
    unchanged (negating a mantissa gives −m·2^e, the scale is untouched); reusing `gate_b_n` on
    the same `ctr` wires would negate the exponents in the complex modes 10/11.
  - **Idle-min = all-zeros relies on unsigned exponents** (ties into the §10 encoding decision: a
    signed encoding would need the most-negative code as the idle value instead).
  - The scale sum is **not** formed in the dispatchers — the A and B exponents come from
    different instances (row vs column) and only meet at the PE: `pe_array_bfp` takes the two
    6-bit arrays (`exp_a_dp8_i` / `exp_b_dp8_i`) and forms the 7-bit per-DP8 scale with one
    `add_n` per DP8 (6 + 6 → 7, exact).

  Verified in `tb_disp_array_exp_bfp` (the 11 mode control vectors + a random-control sweep) and
  end-to-end through the tree in `tb_pe_array_bfp`.
- **`ctrl`** — no new outputs for alignment or exponent dispatch: the aligners self-activate on
  unequal exponents, and the exponent dispatchers reuse `sel_a`/`sel_b`/`ctr_l`/`ctr_h` (wider
  fan-out only). Remaining decode: BFP enable. Open: 4-bit `mode_i` has 5 free codes for 11 BFP
  duals → orthogonal `bfp_i` flag vs widened mode field.
- **Alignment block (functional contract)** — two-operand align: in `(M0, E0)`, `(M1, E1)`; out
  `M0'`, `M1'` at the common scale `E = max(E0, E1)`, the smaller-exponent operand
  arithmetic-right-shifted by |E0 − E1|, operand positions preserved. Tree instances run it on
  carry-save pairs (two rows per operand, shared exponent logic and selects); the acc instance on
  tap pair vs acc row. Internals (per-row carry-save shift semantics, rounding, |Δ| clamp/flush)
  deliberately open (§10).
- **Square variant — BFP scheme (decided).** BFP stays a pure exponent sideband on the mantissa
  datapath: the squarer works on **integer mantissas** (`(m_a+m_b)²−m_a²−m_b² = 2·m_a·m_b`,
  exact), and per DP8 `j` the identity locks all four terms to the block's single scale
  `E_j = e_A,j + e_B,j`: `2·P_j = PE_j − α_j − β_j + C_j`, every term weighted `2^{E_j}`. That
  single-scale lock is what the architecture exploits:
  - **α/β = square arrays only — no trees.** The per-row α generator and per-column β generator
    are just the 16 `dp_8_alpha_sqr` / `dp_8_beta_sqr` (+ centering gates): **no reduction, no
    alignment, no exponents anywhere near them** (pure A-mantissa / pure B-mantissa, fully
    shared). Their per-DP8 carry-save pairs fan into every PE of the row/column.
  - **Per-DP8 combine at L0, before the first align cell.** Each PE folds
    `PE_j − α_j − β_j + C_j` with a per-DP8 combine CPR (~7:2 — PE 2 rows, α 2, β 2, `C`) —
    exact, **no alignment**, since all rows sit at the same scale `E_j`. The combined nodes then
    reduce through **one** tree with the standard `align_cell_bfp` at the L0/L2/L3 merges, driven
    by the per-DP8 `E_j` sideband exactly as the baseline `pe_array_bfp` (exp `add_n` per DP8,
    same sites, same per-mode activation). The ½ stays a single `>>1` at the accumulator; with
    all exponents equal (δ≡0) the path is bit-exact to the integer square.
  - **Why this shape**: exponent locality holds by construction — the generators never see an
    exponent, all exponent work lives in the PE tree, which owns the full sideband (no deferred
    merges, no extra accumulator operands); the integer square's α/β reduction trees are deleted
    while the expensive squares stay shared; and the combine cancels early — `|2·P_j| ≤ 2^14` signed, *narrower*
    than the raw 18-bit square-sums — so from L0 up the tree returns to baseline-like widths
    (+1 bit for the 2×).
  - **Build**: the module ladder, the per-DP8 `pe_array_sqr_bfp` dataflow, the `acc_array_sqr_bfp`
    detail and the open build decisions live in **§9** — the single source of truth for the *how*
    (do not restate the module list here).
  - **Cost to characterize (the comparison goal)**: the α/β per-DP8 fan-out (~2× the old
    tap-level fan-out) and the 16 per-DP8 combine CPRs, versus the baseline's per-PE aligners —
    a clean area/power question with no precision or exponent entanglement.
  - **Formulas**: all 12 modes in [square-bfp/](formulas/square-bfp/) — (mantissa, exponent)-pair
    semantics, per-merge `δ_k = E − E_k` on the full exponents (no external scale), Step 5 = the
    hardware order (per-DP8 combine → aligned merge).

## 9. Square-BFP implementation plan (build ladder)

The actionable spec for building the §8 square-BFP scheme. Verified algebraically for all 12 modes
in [square-bfp/*.tex](formulas/square-bfp/); baseline BFP is built and verified, so its exponent
machinery (dispatchers, `add_n` scale, `align_cell_bfp`, running-max accumulator) is reused directly.

**Key framing.** `pe_array_sqr_bfp`'s reduction tree is **`pe_array_bfp`'s tree, not
`pe_array_sqr`'s**. Once each DP8 is combined to `2·P_j = PE_j − α_j − β_j + C_j` (a *signed* value
at the single block scale `E_j = e_A,j + e_B,j`), the leaves are exactly `2×` the integer int8×int4
dot product — so the aligned/crossed tree, the per-DP8 `add_n` exponent and the `align_cell_bfp`
sites are lifted from `pe_array_bfp` with **+1 bit** widths. Only the **leaf front-end** (squares +
combine + `C` + block-negate) and the α/β **generators** are square-specific.

### Reused unchanged
`dp_8_sqr`, `dp_8_alpha_sqr`, `dp_8_beta_sqr`, `s_5_bit_sqr`, `comp_n`, `gate_n_sqr`,
`gate_n_beta_sqr`; the BFP primitives `align_cell_bfp` / `sub_n_bfp` / `shift_n_bfp`; `ctrl_sqr`,
`disp_array_a_sqr`, `disp_array_b_sqr`; generic `mux_n` / `add_n` / `cpr_w_n` / `reg_n` / `icg`.

### New modules (7)

| Module | Derived from | Change |
| ------ | ------------ | ------ |
| `disp_array_exp_a_sqr_bfp`, `disp_array_exp_b_sqr_bfp` | baseline `disp_array_exp_{a,b}_bfp` | near-copy; ZERO-gate on the square dispatcher's idle codes |
| `pe_array_alpha_sqr_bfp`, `pe_array_beta_sqr_bfp` | `pe_array_{alpha,beta}_sqr` | **delete the tree** → square array only; emit the 16 per-DP8 `−α_j`/`−β_j` carry-save pairs; **no exponents** |
| `const_sqr_bfp` | `const_sqr` | emit **per-DP8** `C_j` (centering + α/β one's-comp `+4` + block-negate `−2N`), **idle-gated** (a zeroed DP8 → `C_j = 0`) |
| `pe_array_sqr_bfp` | `pe_array_bfp` tree **+** square front-end | 16× `dp_8_sqr` → 16× per-DP8 combine CPR (`PE_j − α_j − β_j + C_j`) → `add_n` scale per DP8 → the `pe_array_bfp` aligned crossed tree (widths **+1**); `comp_n` block-negate relocated onto the combined L0 lo legs |
| `acc_array_sqr_bfp` | `acc_array_bfp` **+** square shifts | add `<<1` on the acc row and `>>1` on the resolved output (the ½); single 2-row tap set; **no `C`/`c_neg` ports** |
| `pe_sqr_bfp` | `pe_bfp` | mask (incl. exp operands) + acc & acc_exp pipeline regs + `pe_array_sqr_bfp` + `acc_array_sqr_bfp`; α/β per-DP8 fan-in ports |
| `top_NxN_sqr_bfp` | `top_NxN_bfp` + `top_NxN_sqr` | `ctrl_sqr` + `const_sqr_bfp` + mantissa & exp dispatchers + α/β **square-array** generators per row/col + `pe_sqr_bfp` grid |

### `pe_array_sqr_bfp` — dataflow (the crux)
Per PE:
1. **PE squares** — 16× `dp_8_sqr` on the masked A/B mantissas → 16 carry-save `PE_j` (18-bit unsigned).
2. **α/β in** — 16 `−α_j` pairs (row generator) + 16 `−β_j` pairs (column generator); 16 `C_j` (from `const_sqr_bfp`); `neg_i` (modes 10/11).
3. **Per-DP8 combine** — 16× CPR ~7:2 folding `{PE_j(2), −α_j(2), −β_j(2), C_j(1)}` → one carry-save pair `D_j = 2·P_j`. **No alignment** (all rows share scale `E_j`); `|2·P_j| ≤ 2^14` signed → narrower than the 18-bit square-sums.
4. **Exponent** — 16× `add_n` (6+6→7) → `E_j = e_A,j + e_B,j`, exactly as `pe_array_bfp`.
5. **Tree** — the `pe_array_bfp` aligned crossed tree fed by `D_j`/`E_j`: `align_cell_bfp` before the CPR at L0/L2/L3 (per-mode activation from §6), L1 recombine (same-exp, no align), one L0 register, data + exponent tap exports. Widths = `pe_array_bfp` **+1** (signed `2P`).
6. **Block-negate** — modes 10/11 `comp_n` on the combined L0 lo legs (relocated from `pe_array_sqr`'s pre-tree slot); its `+2` deferral folds into `C_j`.

### `acc_array_sqr_bfp`
`acc_array_bfp` (per-lane `align_cell_bfp`, running-max exponent register, seed ≡ feedback format,
lane fusion) **plus** the square's two shifts: `<<1` on the acc row entering the CPR and an
arithmetic `>>1` on the resolved sum before the register (the ½). Single 2-row tap set (the tree
already delivers `2P`); **no `C`/`c_neg` ports** (C is upstream, per-DP8). Register holds
`P + acc` — the running product sum at its BFP scale.

### Open decisions (settle during build)
1. `−α/−β` complement location — in the generator (shared) vs per-PE at the combine; composition with the block-negate.
2. `comp_n` block-negate on the `2·P_j` domain — confirm the one's-complement stays clean.
3. per-DP8 `C_j` mechanism — 16-entry mode LUT vs derive from per-DP8 `is_signed`; idle-gate source.
4. width/guard pass — signed `2P` through combine→tree; `acc_array_sqr_bfp` `CARRY` headroom for `2·acc + 2P`.

### Build ladder (bottom-up; one component + its tb per gate; explicit per-gate approval)
1. `disp_array_exp_{a,b}_sqr_bfp` + tb — exp dispatch with square idle gating.
2. `pe_array_{alpha,beta}_sqr_bfp` + tb — tree-less square arrays (golden = 16 per-DP8 `−α`/`−β`).
3. `const_sqr_bfp` + tb — per-DP8 `C_j`, idle-gated (golden = the sheets' per-DP8 `c`).
4. `pe_array_sqr_bfp` + tb — **the crux**; driven through the dispatchers + α/β arrays; Pass A equal-exp bit-exact vs integer `pe_array_sqr`, Pass B exponent-exact + bounded value window.
5. `acc_array_sqr_bfp` + tb — full chain into the accumulator (mirror `tb_acc_array_bfp`): Pass A bit-exact, Pass B min-scale seed accumulation.
6. `pe_sqr_bfp`, `top_NxN_sqr_bfp` + `tb_top_NxN_sqr_bfp` — streaming (single-shot / accumulate / scaling × equal- and distinct-exponent), independent software-dispatch golden.

### Verification & constraints
Independent software golden (no DUT-internal reads); all-equal exponents ⇒ bit-exact to the integer
square. **Simulate ≤ 2×2** (time). Diagrams (`pe_array_sqr_bfp`, `acc_array_sqr_bfp`, `pe_sqr_bfp`,
`top_NxN_sqr_bfp`) and this section's status update follow the verified RTL, per prior convention.

## 10. Open items (agenda)

Numeric semantics:

- Exponent encoding and bias per width (5/6/7 bits); value semantics `m · 2^(e−bias)`.
- Output exponent range and saturation/renormalization policy — `e_A + e_B + normalization` spans
  more than the 5–7 stored bits.
- Rounding: truncate-vs-round in the alignment shifts and in the output quantization. **Settled
  for the datapath: truncate everywhere in-loop** (each tree/acc aligner floors toward −∞); the
  single rounding stays at the output quantization stage. A nearest-rounding adder inside the
  single-cycle accumulate loop would cost timing exactly where it can least be afforded.
- **Accumulator truncation semantics (decided, modelled in `tb_acc_array_bfp`)**: the per-lane
  accumulator scale is a **running max** (non-decreasing within a run). Two flooring events, both
  bounded: when an incoming tap has the larger exponent the **accumulator value** rescales (one
  arithmetic-right-shift, ≤1 ulp lost at the new scale per event); when the accumulator has the
  larger exponent the **tap pair** floors (sum and carry rows independently, ≤2 ulp low-side per
  contribution — the same carry-save flooring the tree has). No rounding, LSB side only; a
  min-scale seed floors once on its first alignment and every later equal-scale add is exact
  (verified bit-exact). The exact wide-accumulator alternative is the §10 low-priority align-to-min
  note.
- **Seed / accumulator exponent format (decided)**: `acc_exp_i` is a **7-bit product-domain scale**
  (`e_A + e_B`, carrying 2×bias), one per lane, mirroring `acc_i`; external seed format ≡ register
  feedback format, so the accumulate muxes select same-shape operands and the datapath stays
  bias-blind. Software provides fresh seeds in the product domain (`e_format + B`). Open only: the
  output stage's inverse (strip one bias to storage format) and, if the normalize output is looped
  back, keeping that loop domain-preserving.
- RBFP16B1 exact semantics (dedicated exponent field, hidden bit / subnormals or plain integer
  mantissa) — to confirm.
- **Low priority — align-to-min alternative (evaluated, kept for later)**: alignment right-shifts
  to the max exponent (bounded loss, ≤1 ulp per aligned carry-save bundle, LSB side, amplified by
  later radix shifts). Left-shifting to the min exponent instead would be exact — no truncation,
  even per carry-save row — but requires node widths grown by the full scale range (~+126 bits,
  the Kulisch exact-accumulator design point) and, at fixed width, overflows MSBs (unbounded
  error), which is why FP hardware universally aligns small-to-large. Middle grounds if accuracy
  ever demands: absorb small deltas in the ~2–3 spare guard bits (marginal gain, bidirectional
  shifter), or an exact wide accumulator at the acc stage only (one register per lane, where the
  carry-propagate resolve already exists — the spot where cancellation accuracy would pay).

System-level:

- Chaining: X blocks (1/2/4/8 × 16-bit) feeding later int16/C16 operands must be re-blocked to
  8-element / 4-complex blocks with a common exponent (the §4 minimum) — a documented software
  conversion.
- `acc_i` seed-exponent port: **decided** — `acc_exp_i`, 7-bit product-domain scale per lane (see
  the accumulator format note above); built in `acc_array_bfp`.

Micro-architecture (baseline plan §8; square build ladder §9; remaining):

- Alignment-block internals: **decided/built** — per-row carry-save arithmetic-right-shift
  (each row floors independently), truncate (no rounding), natural fill-window flush (no explicit
  |Δ| clamp). Built as `align_cell_bfp` (`sub_n_bfp` + `mux_n` + `shift_n_bfp`), used in the tree
  and the accumulator; golden model is the cascade/window in `tb_pe_array_bfp` and
  `tb_acc_array_bfp`.
- Timing/pipeline fit: the L0 aligners land in stage 1; the acc aligner sits inside the
  single-cycle accumulate loop (not pipelinable without changing the II) — check at `post-syn-sta`;
  the output normalize/pack stage may need latency 3 → 4.
- `ctrl`/mode encoding: orthogonal `bfp_i` flag vs widened `mode_i`.
- Square-variant BFP: **scheme §8, build ladder §9**; all 12 formula sheets done
  ([square-bfp/](formulas/square-bfp/)). Pending: execute the §9 ladder (gate protocol) and
  characterize area/power vs the baseline BFP.
- Golden-model/testbench strategy: BFP golden = align + integer matmul; degenerate exponents (all
  equal) must reproduce today's integer modes bit-exactly.

## 11. References

- Format layouts (bit-level, authoritative): [modes.xlsx](formulas/modes.xlsx), tab **BFP**.
- Integer-mode storage/dispatch: [modes.xlsx](formulas/modes.xlsx), tabs **Overview** / **Modes**
  (the `Parallel` column defines modes 9/10 as 2 ∥).
- Mode decode ground truth: [ctrl.sv](../rtl/ctrl.sv) (`SEL_A/SEL_B/CTR_*/IS_SIGNED_*` LUTs);
  dispatchers: [disp_array_a.sv](../rtl/disp_array_a.sv), [disp_array_b.sv](../rtl/disp_array_b.sv).
- Baseline architecture: [top_NxN](../wiki/architectures/top_NxN.md); square variant:
  [top_NxN_sqr](../wiki/architectures/top_NxN_sqr.md), [square_imp.md](formulas/square/square_imp.md).
