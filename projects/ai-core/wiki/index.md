# AI-Core Wiki

LLM-authored design documentation for the **ai-core** project. Each page summarizes and cross-references the project's own `rtl/`, `tb/`, and `doc/` sources and links back to them. See [log.md](log.md) for the change history.

> Organized as: **architectures/** — the top-level assemblies, one per variant (currently the baseline `top_pe_bas`); **modules/** — the reusable building blocks (the datapath sub-blocks and the primitive library); **testbenches/** — the self-checking testbenches (`tb_<module>`); plus `concepts/`, `decisions/`, `experiments/`, `references/`. The baseline PE (`top_pe_bas`) is built and verified end to end.

## Architectures

* [Processing Element (baseline)](architectures/top_pe_bas.md) — `top_pe_bas`: the baseline PE top level — `pe_ctrl` + `pe_datapath` plus the control-path pipeline registers.

## Modules

* [Dispatch Array](modules/disp_array.md) — `disp_array`: routes the two 256-bit operands to the 16 DP8s (per-pair 4→1 block select + B high/low split + B-gate).
* [PE Array](modules/pe_array.md) — `pe_array`: 16 DP8s + 4-level carry-save shift/compress tree, with a tap (L0–L3) at every level.
* [Accumulator Array](modules/acc_array.md) — `acc_array`: 8 lanes that resolve a tap, accumulate, and fuse lane pairs into 40-bit results.
* [PE Control](modules/pe_ctrl.md) — `pe_ctrl`: combinational mode decoder — a lookup table mapping `mode_i` to every datapath control.
* [PE Datapath](modules/pe_datapath.md) — `pe_datapath`: structural wrapper chaining `disp_array → pe_array → acc_array` (the 3-stage datapath).
* [Dot Product 8](modules/dp_8.md) — `dp_8`: eight int8×int4 MACs, per-operand signedness, 20-bit sign-consistent carry-save output.
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
* [Register N](modules/reg_n.md) — `reg_n`: register bank, SIZE WIDTH-bit registers, shared async reset.

## Testbenches

* [tb_top_pe_bas](testbenches/tb_top_pe_bas.md) — whole-PE matmul at `pe_out` driven only by `mode_i`/operands/`sel_acc`/`acc_i`, all 11 modes, single-shot and accumulating.
* [tb_pe_array](testbenches/tb_pe_array.md) — independent `A·B` matmul over all 11 modes (packs from the Storage table, compares at the taps).
* [tb_acc_array](testbenches/tb_acc_array.md) — `disp→pe→acc` end-to-end matmul at `pe_out`, all 11 modes, single-shot and accumulating.
* [tb_disp_array](testbenches/tb_disp_array.md) — every DP8 operand vs a golden router model, all 11 modes.
* [tb_dp_8](testbenches/tb_dp_8.md) — resolve + sign-consistency of the carry-save dot product, all signedness combos.
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
