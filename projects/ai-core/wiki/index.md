# AI-Core Wiki

LLM-authored design documentation for the **ai-core** project. Each page summarizes and cross-references the project's own `rtl/`, `tb/`, and `doc/` sources and links back to them. See [log.md](log.md) for the change history.

> Organized as: **architectures/** — the top-level assemblies, one per variant (currently the baseline PE grid `top_NxN`); **modules/** — the reusable building blocks (the shared control/dispatch, the PE core and datapath sub-blocks, and the primitive library); **testbenches/** — the self-checking testbenches (`tb_<module>`); plus `concepts/`, `decisions/`, `experiments/`, `references/`. The `N × N` PE grid `top_NxN` — whose single-PE case is simply `N = 1` — is built and verified end to end.

## Architectures

* [PE Grid (baseline)](architectures/top_NxN.md) — `top_NxN`: baseline `N × N` grid of `pe` cores with one shared `ctrl` and per-row/per-column dispatch (`disp_array_a`/`disp_array_b`); row/column enables (`en_row`/`en_col`) scale the active region to any `rows × cols` rectangle; default 2×2, chip 8×8, single PE = N=1.

## Modules

* [Processing Element](modules/pe.md) — `pe`: the self-contained per-PE core — `en_i` operand mask + `pe_array` + `acc_array` + the two acc pipeline registers.
* [Control](modules/ctrl.md) — `ctrl`: shared grid-wide mode decoder + control pipeline — one instance for the whole grid, a lookup table mapping `mode_i` to every datapath control.
* [Dispatch Array A](modules/disp_array_a.md) — `disp_array_a`: A-path dispatch, one per grid row (per-pair 4→1 A-block select, broadcast to the row).
* [Dispatch Array B](modules/disp_array_b.md) — `disp_array_b`: B-path dispatch, one per grid column (4→1 B-block select + high/low split + B-gate, broadcast to the column).
* [Dispatch Array A (Square)](modules/disp_array_a_sqr.md) — `disp_array_a_sqr`: square A dispatch — routes + centers (per-DP8 `gate_a_n_sqr`) + idle-zeros; `+is_signed_a/zero_i`.
* [Dispatch Array B (Square)](modules/disp_array_b_sqr.md) — `disp_array_b_sqr`: square B dispatch — routes + centers (per-DP8 `gate_b_n_sqr`) + idle-zeros; negate/carry dropped.
* [PE Array](modules/pe_array.md) — `pe_array`: 16 DP8s + 4-level carry-save shift/compress tree, with a tap (L0–L3) at every level.
* [PE Array (Square)](modules/pe_array_sqr.md) — `pe_array_sqr`: square-variant PE array — 16× `dp_8_sqr` + the same crossed tree, with the complex negate relocated in as per-block `comp_n`; `neg_i[5:0]`, no `is_signed`.
* [PE Array Alpha (Square)](modules/pe_array_alpha_sqr.md) — `pe_array_alpha_sqr`: per-row A-only correction generator — `pe_array_sqr` with `dp_8_alpha_sqr` cores (B dropped, `+is_signed_b`); same tree/widths/taps. Emits `−α` (one's-complemented taps).
* [PE Array Beta (Square)](modules/pe_array_beta_sqr.md) — `pe_array_beta_sqr`: per-column B-only correction generator — `pe_array_sqr` with `dp_8_beta_sqr` cores (A dropped, `+is_signed_a`/`zero`); same tree/widths/taps. Emits `−β` (one's-complemented taps).
* [Constant LUT (Square)](modules/const_sqr.md) — `const_sqr`: per-mode `C` for `½(PE − α − β + C)` — folds centering `C_real`, the α/β-complement `+4`, and the block-negate `−2N`; makes the accumulator fully additive.
* [Accumulator Array](modules/acc_array.md) — `acc_array`: 8 lanes that resolve a tap, accumulate, and fuse lane pairs into 40-bit results.
* [Dot Product 8](modules/dp_8.md) — `dp_8`: eight int8×int4 MACs, per-operand signedness, 20-bit sign-consistent carry-save output.
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
* [Multiplexer N](modules/mux_n.md) — `mux_n`: SIZE-to-1 multiplexer over WIDTH-bit words.
* [Gate N](modules/gate_n.md) — `gate_n`: zero gate (pass / zero) over SIZE words.
* [Gate B N](modules/gate_b_n.md) — `gate_b_n`: conditioning gate (pass / zero / negate) over SIZE words.
* [Gate A N (Square)](modules/gate_a_n_sqr.md) — `gate_a_n_sqr`: A centering gate (flip AH MSB iff unsigned, AL MSB always) + idle-zero.
* [Gate B N (Square)](modules/gate_b_n_sqr.md) — `gate_b_n_sqr`: B centering gate (flip nibble MSB iff unsigned) + idle-zero; no negate/carry.
* [Complementer N](modules/comp_n.md) — `comp_n`: pass / one's-complement over SIZE words (invert sibling of `gate_n`); relocates the complex block negate into `pe_array_sqr`.
* [Bias Gate N (Square)](modules/gate_n_sqr.md) — `gate_n_sqr`: flag-selected `is_signed ? sign-ext : −8` over SIZE nibbles (`4→5` bit); injects the removed operand's `−8` in the α/β generators.
* [Beta Bias Gate N (Square)](modules/gate_n_beta_sqr.md) — `gate_n_beta_sqr`: fixed `−8` + idle-zero variant of `gate_n_sqr` for the β low block.
* [Register N](modules/reg_n.md) — `reg_n`: register bank, SIZE WIDTH-bit registers, shared async reset.
* [Integrated Clock Gate](modules/icg.md) — `icg`: latch-based clock gate — passes or holds the clock, for per-block gating.

## Testbenches

* [tb_top_NxN](testbenches/tb_top_NxN.md) — `N × N` grid matmul at each PE's `out_q` (distinct A/row, B/col), all 11 modes, one-shot + accumulate + rectangle scaling via `en_row`/`en_col`; default 2×2.
* [tb_pe_array](testbenches/tb_pe_array.md) — independent `A·B` matmul over all 11 modes (packs from the Storage table, compares at the taps).
* [tb_pe_array_sqr](testbenches/tb_pe_array_sqr.md) — `disp_sqr → pe_array_sqr` tree check: golden square-sum + block negate + crossed weighted reduction vs each read-level tap, all 11 modes, corner-biased.
* [tb_pe_array_alpha_sqr](testbenches/tb_pe_array_alpha_sqr.md) — `disp_a_sqr → pe_array_alpha_sqr`: golden α square-sum (removed-B `−8` bias) + block negate + tree vs each tap, all 11 modes.
* [tb_pe_array_beta_sqr](testbenches/tb_pe_array_beta_sqr.md) — `disp_b_sqr → pe_array_beta_sqr`: golden β square-sum (high `−8·au` / low fixed `−8` + idle-zero) + block negate + tree vs each tap, all 11 modes.
* [tb_acc_array](testbenches/tb_acc_array.md) — `disp→pe→acc` end-to-end matmul at `pe_out`, all 11 modes, single-shot and accumulating.
* [tb_disp_array](testbenches/tb_disp_array.md) — every DP8 operand from `disp_array_a`/`disp_array_b` vs a golden router model, all 11 modes.
* [tb_disp_array_sqr](testbenches/tb_disp_array_sqr.md) — square dispatchers vs a golden route + center + idle-zero model, all 11 modes.
* [tb_dp_8](testbenches/tb_dp_8.md) — resolve + sign-consistency of the carry-save dot product, all signedness combos.
* [tb_dp_8_sqr](testbenches/tb_dp_8_sqr.md) — carry-save square-sum vs a golden `Σ 16·(AH+b)²+(AL+b)²`, pre-centered signed nibbles, corner-biased.
* [tb_booth_r4](testbenches/tb_booth_r4.md) — weighted partial-product sum equals `a·b`, all signedness combos.
* [tb_cpr_w_n](testbenches/tb_cpr_w_n.md) — carry-save output resolves to the input sum.
* [tb_cpr_c_n](testbenches/tb_cpr_c_n.md) — carry-save output resolves to the input sum.

## Concepts

_None yet._

## Decisions

_None yet._

## Experiments

_None yet._

## References

_None yet._
