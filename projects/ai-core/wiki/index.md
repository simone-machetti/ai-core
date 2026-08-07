# AI-Core Wiki

LLM-authored design documentation for the **ai-core** project. Each page summarizes and cross-references the project's own `rtl/`, `tb/`, and `doc/` sources and links back to them. See [log.md](log.md) for the change history.

> Organized as: **architectures/** — the top-level assemblies, one per variant (`top_NxN`, its square amortization `top_NxN_sqr`, and the three block-floating-point grids `top_NxN_bfp` / `top_NxN_sqr_bfp` / `top_NxN_bpl_bfp`); **modules/** — the reusable building blocks (the shared control/dispatch, the PE core and datapath sub-blocks, the BFP alignment library, and the primitive library); **testbenches/** — the self-checking testbenches (`tb_<module>`); plus `concepts/`, `decisions/`, `experiments/`, `references/`. All five `N × N` grids — whose single-PE case is simply `N = 1` — are built and verified end to end (the square is bit-exact to the baseline; the BFP variants add an exponent sideband, bit-identical when exponents are equal; the bit-plane grid matches baseline-BFP in value, through a different carry-save encoding).

## Architectures

* [PE Grid (baseline)](architectures/top_NxN.md) — `top_NxN`: baseline `N × N` grid of `pe` cores with one shared `ctrl` and per-row/per-column dispatch (`disp_array_a`/`disp_array_b`); row/column enables (`en_row`/`en_col`) scale the active region to any `rows × cols` rectangle; default 2×2, chip 8×8, single PE = N=1.
* [PE Grid (square)](architectures/top_NxN_sqr.md) — `top_NxN_sqr`: the square `N × N` grid — `ctrl_sqr` + shared `const_sqr` + per-row `{disp_a_sqr + α gen}` + per-col `{disp_b_sqr + β gen}` + N² `pe_sqr` + `icg`. Same interface/behaviour as `top_NxN`; α/β generators share the row/col clock-gate. Verified bit-exact vs `top_NxN` at full streaming throughput (single-shot + accumulate + scaling).
* [PE Grid (BFP)](architectures/top_NxN_bfp.md) — `top_NxN_bfp`: the `top_NxN` grid with the BFP exponent sideband — per-row/column mantissa+exponent dispatch (`disp_array_*` + `disp_array_exp_*_bfp`) into N² `pe_bfp`; per-lane `align_cell_bfp` brings addends to a common max-exponent scale, so it is bit-identical to `top_NxN` when the exponents are equal. Raw un-normalized `out_q`/`out_exp`.
* [PE Grid (Bit-Plane BFP)](architectures/top_NxN_bpl_bfp.md) — `top_NxN_bpl_bfp`: the BFP grid built on bit-plane multiplication — `ctrl` + per-row `disp_array_a`/`disp_array_exp_a_bfp` + per-col `{disp_array_b_bpl_bfp + disp_array_exp_b_bfp}` + N² `pe_bpl_bfp` + `icg`. Each column's dispatcher also emits the per-DP8 pairwise B sums, so those adders are paid N times instead of N². **Smaller than baseline-BFP at every grid size** (crossover N = 1): −3.3 % area at 8×8, −3.5 % at 16×16. Verified 66/66, N=2.
* [PE Grid (Square-BFP)](architectures/top_NxN_sqr_bfp.md) — `top_NxN_sqr_bfp`: the square grid with the BFP sideband — `ctrl_sqr` (reused, no `ctrl_sqr_bfp`) + shared `const_sqr_bfp` + per-row/col `{disp_sqr + disp_exp_sqr_bfp + tree-less α/β gen}` + N² `pe_sqr_bfp`. `A[r]·B[c]` in block floating point via the square identity; verified 66/66 (equal-exp matmul + distinct-exp exponent/mantissa window), N=2.

## Modules

* [Processing Element](modules/pe.md) — `pe`: the self-contained per-PE core — `en_i` operand mask + `pe_array` + `acc_array` + the two acc pipeline registers.
* [Control](modules/ctrl.md) — `ctrl`: shared grid-wide mode decoder + control pipeline — one instance for the whole grid, a lookup table mapping `mode_i` to every datapath control.
* [Processing Element (square)](modules/pe_sqr.md) — `pe_sqr`: the square PE core — `pe_array_sqr` + `acc_array_sqr` + 2 acc regs; takes the shared `−α`/`−β` taps and `c`/`c_neg` as inputs; `en_i` masks A, B and the tap buses for a fully-quiet gated PE.
* [Processing Element (BFP)](modules/pe_bfp.md) — `pe_bfp`: the `pe` core with the exponent sideband — masks the mantissa **and** exponent operands, `pe_array_bfp` + `acc_array_bfp` + twin acc / acc-exp pipeline registers.
* [Processing Element (Square-BFP)](modules/pe_sqr_bfp.md) — `pe_sqr_bfp`: the square-BFP PE core — `pe_array_sqr_bfp` + `acc_array_sqr_bfp` + twin acc/acc-exp regs; α/β/const are folded at L0 upstream, so the accumulator takes one tap set (no `c`/`c_neg`).
* [Processing Element (Bit-Plane BFP)](modules/pe_bpl_bfp.md) — `pe_bpl_bfp`: the bit-plane PE core — `pe_array_bpl_bfp` + `acc_array_bpl_bfp` + twin acc/acc-exp regs; `en_i` masks **five** buses (the pair sums are a third operand); no `is_signed_b_i`, resolved upstream. 5148.90 µm², −3.7 % vs `pe_bfp`.
* [Control (square)](modules/ctrl_sqr.md) — `ctrl_sqr`: the square `ctrl` — `mode →` every square control; drops `ctr_l`/`ctr_h`, adds `zero`/`neg`/`sel_const`; mode-5 all-signed.
* [Dispatch Array A](modules/disp_array_a.md) — `disp_array_a`: A-path dispatch, one per grid row (per-pair 4→1 A-block select, broadcast to the row).
* [Dispatch Array B](modules/disp_array_b.md) — `disp_array_b`: B-path dispatch, one per grid column (4→1 B-block select + high/low split + B-gate, broadcast to the column).
* [Dispatch Array A (Square)](modules/disp_array_a_sqr.md) — `disp_array_a_sqr`: square A dispatch — routes + centers (per-DP8 `gate_a_n_sqr`) + idle-zeros; `+is_signed_a/zero_i`.
* [Dispatch Array B (Square)](modules/disp_array_b_sqr.md) — `disp_array_b_sqr`: square B dispatch — routes + centers (per-DP8 `gate_b_n_sqr`) + idle-zeros; negate/carry dropped.
* [Exponent Dispatch A (BFP)](modules/disp_array_exp_a_bfp.md) — `disp_array_exp_a_bfp`: A-exponent dispatch, one per row — routes each block's 6-bit exponent to its DP8s (duplicated per pair), idle-zeroed by `ctr`.
* [Exponent Dispatch B (BFP)](modules/disp_array_exp_b_bfp.md) — `disp_array_exp_b_bfp`: B-exponent dispatch, one per column — routes the high/low half exponents to the even/odd DP8s.
* [Exponent Dispatch A (Square-BFP)](modules/disp_array_exp_a_sqr_bfp.md) — `disp_array_exp_a_sqr_bfp`: the square A-exp dispatcher — `disp_array_exp_a_bfp` keyed on per-DP8 `zero_i` (idle) instead of `ctr_h`/`ctr_l`.
* [Exponent Dispatch B (Square-BFP)](modules/disp_array_exp_b_sqr_bfp.md) — `disp_array_exp_b_sqr_bfp`: the square B-exp dispatcher — `zero_i`-keyed idle-zero.
* [Dispatch Array B (Bit-Plane BFP)](modules/disp_array_b_bpl_bfp.md) — `disp_array_b_bpl_bfp`: bit-plane B dispatch — `disp_array_b` routing plus one `gate_b_n_bpl_bfp` per DP8, so the column broadcasts 8 × 5-bit exact signed values **and** 4 × 6-bit pairwise sums; consumes `is_signed_b` so the PEs never see it.
* [PE Array](modules/pe_array.md) — `pe_array`: 16 DP8s + 4-level carry-save shift/compress tree, with a tap (L0–L3) at every level.
* [PE Array (Square)](modules/pe_array_sqr.md) — `pe_array_sqr`: square-variant PE array — 16× `dp_8_sqr` + the same crossed tree, with the complex negate relocated in as per-block `comp_n`; `neg_i[5:0]`, no `is_signed`.
* [PE Array Alpha (Square)](modules/pe_array_alpha_sqr.md) — `pe_array_alpha_sqr`: per-row A-only correction generator — `pe_array_sqr` with `dp_8_alpha_sqr` cores (B dropped, `+is_signed_b`); same tree/widths/taps. Emits `−α` (one's-complemented taps).
* [PE Array Beta (Square)](modules/pe_array_beta_sqr.md) — `pe_array_beta_sqr`: per-column B-only correction generator — `pe_array_sqr` with `dp_8_beta_sqr` cores (A dropped, `+is_signed_a`/`zero`); same tree/widths/taps. Emits `−β` (one's-complemented taps).
* [PE Array (BFP)](modules/pe_array_bfp.md) — `pe_array_bfp`: the `pe_array` tree with per-lane `align_cell_bfp` aligners, a per-DP8 scale add and a running exponent max-tree; taps carry data + a 7-bit scale, transparent (= `pe_array`) when exponents match.
* [PE Array (Bit-Plane BFP)](modules/pe_array_bpl_bfp.md) — `pe_array_bpl_bfp`: `pe_array_bfp`'s tree with `dp_8_bpl_bfp` leaves — same 11 aligners and max-tree; `+b_sum_dp8_i`, no `is_signed_b_i`; nodes 31/36/44/44 (a guard bit at L0 and L1), taps 18/36/40/40.
* [PE Array (Square-BFP)](modules/pe_array_sqr_bfp.md) — `pe_array_sqr_bfp`: the square front-end on `pe_array_bfp`'s aligned tree — 16× `dp_8_sqr` + per-DP8 `−α`/`−β`/`C` folded to `2·P` by one `ext_inject_sqr_bfp` (7:2 CPR) *before* a baseline-BFP crossed tree (2-row align, 4:2 CPR); taps +1-bit (19/30/38/39).
* [External-term Injection (Square-BFP)](modules/ext_inject_sqr_bfp.md) — `ext_inject_sqr_bfp`: the per-DP8 square reconstruction front-end — folds `{PE, −α, −β, C}` → `2·P` per block (idle-gate + `comp_n` block-negate + 7:2 CPR) at the block scale `E_j`, reverting the tree above it to baseline-BFP; one instance over all 16 DP8s.
* [PE Array Alpha (Square-BFP)](modules/pe_array_alpha_sqr_bfp.md) — `pe_array_alpha_sqr_bfp`: the tree-less, neg-agnostic per-row `−α` generator — just 16× `dp_8_alpha_sqr` one's-complemented; combinational, its register lives in `pe_array_sqr_bfp`'s L0.
* [PE Array Beta (Square-BFP)](modules/pe_array_beta_sqr_bfp.md) — `pe_array_beta_sqr_bfp`: the tree-less per-column `−β` generator — 16× `dp_8_beta_sqr` one's-complemented, `+zero_i`; combinational.
* [Constant LUT (Square)](modules/const_sqr.md) — `const_sqr`: per-mode `C` for `½(PE − α − β + C)` — folds centering `C_real`, the α/β-complement `+4`, and the block-negate `−2N`; makes the accumulator fully additive.
* [Constant LUT (Square-BFP)](modules/const_sqr_bfp.md) — `const_sqr_bfp`: the per-DP8 constant LUT — `mode →` 16 signed `C_j` (centering `C_cent + 4`, or `2 − C_cent` for negated blocks); combinational, no register, no idle-gate.
* [Accumulator Array](modules/acc_array.md) — `acc_array`: 8 lanes that resolve a tap, accumulate, and fuse lane pairs into 40-bit results.
* [Accumulator Array (Square)](modules/acc_array_sqr.md) — `acc_array_sqr`: all-additive resolve `½(PE − α − β + C)` — triple tap mux + acc-mux `<<1` + const mux (`RH=sign(RL)`) → CPR 8:2 → `add_n` → `÷2` (`>>1` + `H→L` cross-bit). No subtractor; native-unit `acc_i`, true-value register.
* [Accumulator Array (BFP)](modules/acc_array_bfp.md) — `acc_array_bfp`: the `acc_array` with in-loop BFP alignment — per-lane `align_cell_bfp` to `max(acc_exp, tap_exp)`, running-max exponent register, lane-fusion fill chain; transparent (= `acc_array`) when exponents match.
* [Accumulator Array (Bit-Plane BFP)](modules/acc_array_bpl_bfp.md) — `acc_array_bpl_bfp`: `acc_array_bfp` with **only** the tap widths resized for the bit-plane tree (L1/L2/L3 at 36/40/40 instead of 29/37/38); every mechanism unchanged.
* [Accumulator Array (Square-BFP)](modules/acc_array_sqr_bfp.md) — `acc_array_sqr_bfp`: `acc_array_bfp` + the square's `½` (`<<1` acc-row + arithmetic `>>1` output) on one `2·P` tap set; no `c`/`c_neg` (folded upstream); `EXT=CARRY=3`.
* [Dot Product 8](modules/dp_8.md) — `dp_8`: eight int8×int4 MACs, per-operand signedness, 20-bit sign-consistent carry-save output.
* [Dot Product 8 (Bit-Plane BFP)](modules/dp_8_bpl_bfp.md) — `dp_8_bpl_bfp`: bit-plane DP8 — 32 multiplexers selected by A's bit planes over precomputed B partials instead of Booth recoding; 22-bit sign-consistent carry-save, no `is_signed_b_i`. 190.63 µm² standalone, −5.8 % vs `dp_8`.
* [Dot Product 8 (Square)](modules/dp_8_sqr.md) — `dp_8_sqr`: square-variant DP8 — add-then-square (16× `s_5_bit_sqr`) over pre-centered nibbles, 18-bit unsigned carry-save square-sum; drop-in for `dp_8`.
* [Dot Product 8 Alpha (Square)](modules/dp_8_alpha_sqr.md) — `dp_8_alpha_sqr`: A-only α square-sum — `dp_8_sqr` with B removed, the removed-B `−8` injected by two `gate_n_sqr` banks; 18-bit carry-save.
* [Dot Product 8 Beta (Square)](modules/dp_8_beta_sqr.md) — `dp_8_beta_sqr`: B-only β square-sum — `dp_8_sqr` with A removed, `b` squared twice (high `gate_n_sqr` + low `gate_n_beta_sqr`/idle-zero); 18-bit carry-save.
* [Signed 5-bit Squarer](modules/s_5_bit_sqr.md) — `s_5_bit_sqr`: flat K-map-minimized signed 5-bit squarer (`[−16,15]` → unsigned square `[0,256]`); the per-lane square in `dp_8_sqr`.
* [Booth Radix-4](modules/booth_r4.md) — `booth_r4`: radix-4 Booth partial-product generator with per-operand signedness.
* [Booth Radix-4 Cell](modules/booth_r4_cell.md) — `booth_r4_cell`: one selector → one partial product.
* [Wallace Compressor N](modules/cpr_w_n.md) — `cpr_w_n`: N:2 carry-save compressor, Wallace-tree build (max throughput).
* [Cascade Compressor N](modules/cpr_c_n.md) — `cpr_c_n`: N:2 carry-save compressor, serial-cascade build (min area).
* [Full Adder](modules/fa.md) — `fa`: one-bit full adder, the 3:2 cell inside the compressors.
* [Adder N](modules/add_n.md) — `add_n`: two-input adder with a carry chain (WIDTH-bit sum + CARRY-bit carry).
* [Extender N](modules/ext_n.md) — `ext_n`: widen SIZE words by EXT bits (sign or zero).
* [Shifter N](modules/shift_n.md) — `shift_n`: conditional left shifter (width-growing) with a shared select.
* [BFP Alignment Cell](modules/align_cell_bfp.md) — `align_cell_bfp`: the two-bundle align cell — one `sub_n_bfp` compare steers one `shift_n_bfp` (via `mux_n` swap/un-swap) to bring two exponent-sharing bundles to their shared `max`; supports lane-fusion chaining.
* [BFP Aligner](modules/align_bfp.md) — `align_bfp`: the multi-exponent aligner — a binary tree of `align_cell_bfp`s collapsing `NUM_EXP` bundles to one global `max` scale (bit-identical to a single flat shift).
* [Subtractor N (BFP)](modules/sub_n_bfp.md) — `sub_n_bfp`: unsigned compare → magnitude + sign (`|a−b|`, `a<b`), the exponent-difference primitive inside `align_cell_bfp`.
* [Shifter N (BFP)](modules/shift_n_bfp.md) — `shift_n_bfp`: right shifter with a per-row fill input (arithmetic/logical, cross-boundary fill for lane fusion), the shift primitive inside `align_cell_bfp`.
* [Multiplexer N](modules/mux_n.md) — `mux_n`: SIZE-to-1 multiplexer over WIDTH-bit words.
* [Gate N](modules/gate_n.md) — `gate_n`: zero gate (pass / zero) over SIZE words.
* [Gate B N](modules/gate_b_n.md) — `gate_b_n`: conditioning gate (pass / zero / negate) over SIZE words.
* [Gate B N (Bit-Plane BFP)](modules/gate_b_n_bpl_bfp.md) — `gate_b_n_bpl_bfp`: bit-plane B gate — widens each word to its exact signed value (`WIDTH+1`) and emits the `SIZE/2` pairwise sums (`WIDTH+2`); lives in the column dispatch so the adders amortize over the column.
* [Gate A N (Square)](modules/gate_a_n_sqr.md) — `gate_a_n_sqr`: A centering gate (flip AH MSB iff unsigned, AL MSB always) + idle-zero.
* [Gate B N (Square)](modules/gate_b_n_sqr.md) — `gate_b_n_sqr`: B centering gate (flip nibble MSB iff unsigned) + idle-zero; no negate/carry.
* [Complementer N](modules/comp_n.md) — `comp_n`: pass / one's-complement over SIZE words (invert sibling of `gate_n`); relocates the complex block negate into `pe_array_sqr`.
* [Bias Gate N (Square)](modules/gate_n_sqr.md) — `gate_n_sqr`: flag-selected `is_signed ? sign-ext : −8` over SIZE nibbles (`4→5` bit); injects the removed operand's `−8` in the α/β generators.
* [Beta Bias Gate N (Square)](modules/gate_n_beta_sqr.md) — `gate_n_beta_sqr`: fixed `−8` + idle-zero variant of `gate_n_sqr` for the β low block.
* [Register N](modules/reg_n.md) — `reg_n`: register bank, SIZE WIDTH-bit registers, shared async reset.
* [Integrated Clock Gate](modules/icg.md) — `icg`: latch-based clock gate — passes or holds the clock, for per-block gating.

## Testbenches

* [tb_top_NxN](testbenches/tb_top_NxN.md) — `N × N` grid matmul at each PE's `out_q` (distinct A/row, B/col) at full pipeline throughput (fresh operand every clock, pipeline-delayed golden), all 11 modes, streaming single-shot + accumulation (`seed + Σ` tiles) + rectangle scaling via `en_row`/`en_col`; default 2×2.
* [tb_top_NxN_sqr](testbenches/tb_top_NxN_sqr.md) — the square grid as an equivalence oracle: baseline `tb_top_NxN` streaming bench reused verbatim (bit-exact), full-throughput streaming, all 11 modes × 3 passes, N=2, 0 mismatches.
* [tb_top_NxN_bfp](testbenches/tb_top_NxN_bfp.md) — the BFP grid streaming, distinct A/row + B/col per PE; each mode × 3 patterns × 2 exponent experiments (equal-exp bit-exact matmul + distinct-exp exponent/mantissa window), N=2, 0 mismatches.
* [tb_top_NxN_sqr_bfp](testbenches/tb_top_NxN_sqr_bfp.md) — the square-BFP grid as a black box computing `A·B` in BFP; verified like `tb_top_NxN_bfp` (**66/66**: equal-exp bit-exact + distinct-exp square window), N=2.
* [tb_top_NxN_global](testbenches/tb_top_NxN_global.md) — pre-synthesis 3-way equivalence: instantiates **both** `top_NxN` and `top_NxN_sqr`, drives identical streaming inputs, and checks `golden == baseline == square` at every PE (`cmp3` flags `BAS!=GOLD`/`SQR!=GOLD`/`BAS!=SQR`); all 11 modes × 3 passes, N=2, 0 mismatches.
* [tb_top_NxN_bpl_bfp](testbenches/tb_top_NxN_bpl_bfp.md) — the bit-plane BFP grid streaming at full throughput, distinct A/row + B/col; each mode × 3 patterns × 2 exponent experiments (equal-exp bit-exact matmul + distinct-exp exponent/mantissa window), **66/66**, N=2, 0 mismatches.
* [tb_pe_array](testbenches/tb_pe_array.md) — independent `A·B` matmul over all 11 modes (packs from the Storage table, compares at the taps).
* [tb_pe_array_sqr](testbenches/tb_pe_array_sqr.md) — `disp_sqr → pe_array_sqr` tree check: golden square-sum + block negate + crossed weighted reduction vs each read-level tap, all 11 modes, corner-biased.
* [tb_pe_array_alpha_sqr](testbenches/tb_pe_array_alpha_sqr.md) — `disp_a_sqr → pe_array_alpha_sqr`: golden α square-sum (removed-B `−8` bias) + block negate + tree vs each tap, all 11 modes.
* [tb_pe_array_beta_sqr](testbenches/tb_pe_array_beta_sqr.md) — `disp_b_sqr → pe_array_beta_sqr`: golden β square-sum (high `−8·au` / low fixed `−8` + idle-zero) + block negate + tree vs each tap, all 11 modes.
* [tb_pe_array_bfp](testbenches/tb_pe_array_bfp.md) — `disp → pe_array_bfp` with the baseline `pe_array` alongside; Pass A equal-exp taps bit-identical to the integer tree, Pass B distinct-exp max-tree + truncation window, all 11 modes.
* [tb_pe_array_sqr_bfp](testbenches/tb_pe_array_sqr_bfp.md) — `disp_sqr → pe_array_sqr_bfp` crossed tree over the reconstructed `2·P` leaves (tb supplies `−α`/`−β`/`C`); Pass A bit-exact `2·A·B`, Pass B distinct-exp window, all 11 modes.
* [tb_pe_array_alpha_sqr_bfp](testbenches/tb_pe_array_alpha_sqr_bfp.md) — `disp_a_sqr → pe_array_alpha_sqr_bfp`: the 16 per-DP8 `−α` outputs vs a `dp_8_alpha_sqr` golden (`−ALPHA_DP8 − 2`, idle `−2`), all 11 modes.
* [tb_pe_array_beta_sqr_bfp](testbenches/tb_pe_array_beta_sqr_bfp.md) — `disp_b_sqr → pe_array_beta_sqr_bfp`: the 16 per-DP8 `−β` outputs vs a `dp_8_beta_sqr` golden (`−BETA_DP8 − 2`, idle `−2`), all 11 modes.
* [tb_pe_array_bpl_bfp](testbenches/tb_pe_array_bpl_bfp.md) — `disp_array_b_bpl_bfp → pe_array_bpl_bfp` with the baseline `pe_array` alongside; Pass A equal-exp taps carry the same **value** as the integer tree (the carry-save encoding legitimately differs), Pass B distinct-exp max-tree + window, all 11 modes.
* [tb_acc_array](testbenches/tb_acc_array.md) — `disp→pe→acc` end-to-end matmul at `pe_out`, all 11 modes, single-shot and accumulating.
* [tb_acc_array_sqr](testbenches/tb_acc_array_sqr.md) — whole square path (`disp → pe∥α∥β → const → acc`) as an equivalence oracle: `pe_out` == baseline matmul, all 11 modes × 2000, single-shot + accumulation, 0 mismatches.
* [tb_acc_array_bfp](testbenches/tb_acc_array_bfp.md) — whole BFP path (`disp → pe_array_bfp → acc_array_bfp`) vs the integer path + matmul golden; Pass A equal-exp bit-identical (single-shot + accumulate), Pass B min-scale-seed closed form, all 11 modes.
* [tb_acc_array_sqr_bfp](testbenches/tb_acc_array_sqr_bfp.md) — whole square-BFP path vs the integer square path + matmul golden (three agree); Pass A `b_pe_out === pe_out === X`, Pass B in-loop align + `½` closed form, all 11 modes.
* [tb_acc_array_bpl_bfp](testbenches/tb_acc_array_bpl_bfp.md) — whole bit-plane BFP path (`disp → pe_array_bpl_bfp → acc_array_bpl_bfp`) vs the integer path + matmul golden; Pass A equal-exp agreement at `pe_out` on **all 8 lanes**, single-shot + accumulate, Pass B min-scale-seed closed form, all 11 modes.
* [tb_disp_array](testbenches/tb_disp_array.md) — every DP8 operand from `disp_array_a`/`disp_array_b` vs a golden router model, all 11 modes.
* [tb_disp_array_sqr](testbenches/tb_disp_array_sqr.md) — square dispatchers vs a golden route + center + idle-zero model, all 11 modes.
* [tb_disp_array_bpl_bfp](testbenches/tb_disp_array_bpl_bfp.md) — the bit-plane dispatch pair (`disp_array_a` + `disp_array_b_bpl_bfp`) vs a golden of the whole chain: route, H/L split, gate **with the cross-half negate carry**, signed widening, pair sums; all 11 modes on `ctrl`'s real control vectors.
* [tb_disp_array_exp_bfp](testbenches/tb_disp_array_exp_bfp.md) — the BFP exponent dispatchers vs a golden router (block-select + H/L split + per-half ZERO-only mask); modes 10/11 negate-never-touches-scale, 5/6 idle-half mask, + a random sweep.
* [tb_disp_array_exp_sqr_bfp](testbenches/tb_disp_array_exp_sqr_bfp.md) — the square-BFP exponent dispatchers vs a golden router with the per-DP8 `zero_i` mask; modes 5/6 partly-idle pair, + a random sweep.
* [tb_dp_8](testbenches/tb_dp_8.md) — resolve + sign-consistency of the carry-save dot product, all signedness combos.
* [tb_dp_8_sqr](testbenches/tb_dp_8_sqr.md) — carry-save square-sum vs a golden `Σ 16·(AH+b)²+(AL+b)²`, pre-centered signed nibbles, corner-biased.
* [tb_dp_8_bpl_bfp](testbenches/tb_dp_8_bpl_bfp.md) — resolve + sign-consistency + value-equivalence against `dp_8`, all four signedness combos; corner-biased because the tightest compressor stage sits only ~6 % inside the sign-consistency bound.
* [tb_booth_r4](testbenches/tb_booth_r4.md) — weighted partial-product sum equals `a·b`, all signedness combos.
* [tb_cpr_w_n](testbenches/tb_cpr_w_n.md) — carry-save output resolves to the input sum.
* [tb_cpr_c_n](testbenches/tb_cpr_c_n.md) — carry-save output resolves to the input sum.
* [tb_align_cell_bfp](testbenches/tb_align_cell_bfp.md) — the two-bundle align cell (signed H/L pair + chain + unsigned standalone) vs a flat value-level golden: shift-to-max, winner pass-through, chained fusion, `exp_o = max`.
* [tb_align_bfp](testbenches/tb_align_bfp.md) — the multi-exponent aligner tree (signed + unsigned) vs the single flat shift: all-equal transparent, one-hot deep-flush, corner-biased deltas.

## Concepts

_None yet._

## Decisions

_None yet._

## Experiments

* [Synthesis Area](experiments/syn_area.md) — the five grids' cell area at 8×8 and 16×16, each square measured against **its own baseline** (per-component pass A, blackbox-linked 2×2 pass B, grid totals assembled from a per-N count model — no 8×8/16×16 grid is synthesized). Square is −0.9 % / −6.9 % (crossover N ≈ 7.5); **Square-BFP reaches parity with Baseline-BFP** (+2.6 % at 8×8, −0.0 % at 16×16, crossover N ≈ 16) — the payoff of the per-DP8 7:2 reconstruction (which brings `pe_sqr_bfp` below `pe_bfp`) plus the tree-less α/β generators. **Bit-Plane BFP is below Baseline-BFP at every size** (−3.3 % / −3.5 %, crossover **N = 1**) — its N term is one widened dispatcher (+32 %) rather than two extra arrays. The BFP sideband itself costs ~40 % area.
* [Synthesis Power](experiments/syn_pwr.md) — the five grids' VCD-annotated dynamic power at 100 vectors/mode, measured on the complete 2×2 grids and assembled per component for the larger sizes (gate-level simulation of an 8×8 does not fit in memory). Square is −8.9 % / −16.1 % (crossover N ≈ 4.9); Square-BFP −2.6 % / −6.4 % (crossover N ≈ 6.0); Bit-Plane BFP only −0.30 % / −0.75 % (crossover N ≈ 5.9) — it removes gates far better than it removes toggling. The BFP sideband costs ~34 % power; both power crossovers land earlier than their area counterparts.
* [Per-Mode Synthesis Power](experiments/syn_mode_pwr.md) — the same 5-variant comparison measured once per operating mode instead of averaged over all 11. The square's 8×8 margin runs **−22.4 % (mode 6) to +1.4 % (mode 1)**, the square-BFP's **−14.1 % to +4.8 %**; both the N² per-tile saving and the N α/β overhead scale with the mode, so the crossover spans **N ≈ 2.2 to 20**. Square wins 10/11 at 8×8 and 11/11 at 16×16; Square-BFP wins 8/11 at 8×8 (loses 1, 3, 7) and 10/11 at 16×16 — both losing mode 1. **Bit-Plane BFP has the widest spread of all: −11.2 % to +23.1 %**, wins 6/11 at both sizes, and its margin tracks `sel_shift` almost exactly (0 shifts → +23 %, 3 shifts → −11 %); four modes have a *negative* per-tile saving, so no grid size ever recovers them.
* [Intra-PE Area](experiments/syn_pe_area.md) — the area breakdown *inside* one PE, at the DP level (the 16 dot-product cores alone) and the PE level (DP8 array / compression tree / accumulator / glue). The squarer is **−38 %** against the multiplier at the arithmetic core and BFP costs nothing there, but the reconstruction has to be paid: it lands in the accumulator (`acc_array_sqr` is 2.4× `acc_array`) and, inside BFP, in the tree, leaving **−13.0 %** and **−2.6 %** at PE level. The bit-plane core is −6.0 % but hands up a wider row, giving the tree back +10.4 %, for **−3.7 %** net. Boundary-preserved synthesis, so hierarchical totals run 12–14 % above flat.
* [Grid Scaling](experiments/syn_scaling.md) — the same instance-count model evaluated over N = 2…128 instead of two fixed sizes, so the 8×8/16×16 bars are two points on these curves by construction. Area crossover **N = 7.4** (square), **15.9** (square-BFP) and **1.0** (bit-plane); power **N = 4.9**, **6.0** and **5.9** — power turns positive before area on the two square axes and *after* it on the bit-plane one. The asymptotes (**−13.0 % / −2.6 % / −3.7 %** area, **−23.7 % / −10.4 % / −1.2 %** power) are the per-PE ratios, i.e. the gain once the per-row/column overhead is amortized away.

## References

_None yet._
