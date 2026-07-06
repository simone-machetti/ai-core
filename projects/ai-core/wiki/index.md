# AI-Core Wiki

LLM-authored design documentation for the **ai-core** project, written in the Open Knowledge Format (OKF v0.1). Each page summarizes and cross-references the project's own `rtl/`, `tb/`, and `doc/` sources and links back to them through its `resource:` field. See [log.md](log.md) for the change history.

> The **built-and-verified** blocks are documented below (the primitive library, the DP8 core, the dispatch array, and the PE array), together with their testbenches under **Verification**. The remaining higher-level blocks (`acc_array`, `pe_ctrl`, `pe_top`) are not yet defined and are intentionally not documented here. Pages are added under the matching folder (`architecture/`, `modules/`, `verification/`, `concepts/`, `decisions/`, `experiments/`, `references/`).

## Architecture

* [Dispatch Array](architecture/disp_array.md) — `disp_array`: routes the two 256-bit operands to the 16 DP8s (per-pair 4→1 block select + B high/low split + B-gate).
* [PE Array](architecture/pe_array.md) — `pe_array`: 16 DP8s + 4-level carry-save shift/compress tree, with a tap (L0–L3) at every level.

## Modules

* [Dot Product 8](modules/dp_8.md) — `dp_8`: eight int8×int4 MACs, per-operand signedness, 18-bit carry-save output.
* [Booth Radix-4](modules/booth_r4.md) — `booth_r4`: radix-4 Booth partial-product generator with per-operand signedness.
* [Booth Radix-4 Cell](modules/booth_r4_cell.md) — `booth_r4_cell`: one selector → one partial product.
* [Wallace Compressor N](modules/cpr_w_n.md) — `cpr_w_n`: N:2 carry-save compressor, Wallace-tree build (max throughput).
* [Cascade Compressor N](modules/cpr_c_n.md) — `cpr_c_n`: N:2 carry-save compressor, serial-cascade build (min area).
* [Full Adder](modules/fa.md) — `fa`: one-bit full adder, the 3:2 cell inside the compressors.
* [Adder N](modules/add_n.md) — `add_n`: two-input adder with a WIDTH+1 (overflow-safe) result.
* [Extender N](modules/ext_n.md) — `ext_n`: widen SIZE words by EXT bits (sign or zero).
* [Shifter N](modules/shift_n.md) — `shift_n`: conditional left shifter (width-growing) with a shared select.
* [Multiplexer N](modules/mux_n.md) — `mux_n`: SIZE-to-1 multiplexer over WIDTH-bit words.
* [Gate A N](modules/gate_a_n.md) — `gate_a_n`: zero gate (pass / zero) over SIZE words.
* [Gate B N](modules/gate_b_n.md) — `gate_b_n`: conditioning gate (pass / zero / negate) over SIZE words.
* [Register N](modules/reg_n.md) — `reg_n`: register bank, SIZE WIDTH-bit registers, shared async reset.

## Verification

* [PE Array Testbench](verification/pe_array.md) — `tb_pe_array`: independent `A·B` matmul over all 11 modes (packs from the Storage table, compares at the taps).
* [Dispatch Array Testbench](verification/disp_array.md) — `tb_disp_array`: every DP8 operand vs a golden router model, all 11 modes.
* [Dot Product 8 Testbench](verification/dp_8.md) — `tb_dp_8`: resolve + sign-consistency of the carry-save dot product, all signedness combos.
* [Booth Radix-4 Testbench](verification/booth_r4.md) — `tb_booth_r4`: weighted partial-product sum equals `a·b`, all signedness combos.
* [Wallace Compressor N Testbench](verification/cpr_w_n.md) — `tb_cpr_w_n`: carry-save output resolves to the input sum.
* [Cascade Compressor N Testbench](verification/cpr_c_n.md) — `tb_cpr_c_n`: carry-save output resolves to the input sum.

## Concepts

_None yet._

## Decisions

_None yet._

## Experiments

_None yet._

## References

_None yet._
