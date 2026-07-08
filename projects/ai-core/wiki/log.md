# Log

Change history for the AI-Core wiki — newest first. Entries follow OKF: grouped by ISO-8601 date, each line `**[Action]**: description`.

## 2026-07-08

- **[Change]**: Reorganized the wiki for architecture variants. Renamed the baseline PE top level `pe_bas` → `top_pe_bas` (RTL, tb, wiki, diagrams). Split the catalog into `architectures/` — top-level assemblies only, currently [top_pe_bas](architectures/top_pe_bas.md) — and `modules/`, which now holds every lower-level module: the datapath sub-blocks `disp_array`/`pe_array`/`acc_array`/`pe_ctrl`/`pe_datapath` moved in alongside the primitive library. Renamed `verification/` → `testbenches/` with pages named `tb_<module>`. Removed the `doc/diagrams/*.md` companions now covered by the wiki (kept the `.excalidraw`/`.png` figures and `modes.md`), and renamed the `pe_matrix` figure → `top_8x8_bas` (the future 8×8 grid, unbuilt). Made every reusable module header architecture-agnostic — no top-level variant names. Re-verified `top_pe_bas` end to end (11/11, single-shot + accumulating).

## 2026-07-07

- **[Creation]**: Completed the PE — added [pe_ctrl](./modules/pe_ctrl.md) (combinational mode decoder: a `mode_i`-indexed lookup table driving every datapath control; `prop_carry` derived from `sel_out`), [pe_datapath](./modules/pe_datapath.md) (structural `disp_array → pe_array → acc_array` wrapper, taps internal), and [top_pe_bas](./architectures/top_pe_bas.md) (`pe_ctrl` + `pe_datapath` plus the control-path pipeline registers that delay each control to its stage: input reg for `mode`/`sel_acc`/`acc`, group-2 reg for `sel_shift[2:1]`/`sel_out`/`prop_carry`, group-3 reg for `sel_acc`/`acc`; `sel_shift` reassembled with bit 0 combinational). Verified whole-PE across all 11 modes, single-shot and accumulating, driven only by `mode_i`/operands/`sel_acc`/`acc_i`, with [tb_top_pe_bas](./testbenches/tb_top_pe_bas.md). Added the three architecture pages, the verification page, and the `index.md` entries.
- **[Fix]**: `doc/diagrams/top_pe_bas.md` — refreshed for the built RTL: `ctr_l`/`ctr_h` are 2-bit (pass/zero/negate) per pair, the internal tap-level select is `sel_out` (dropped the `sel_tap` working name), the pipeline is a confirmed 3-stage (disp input / `pe_array` L0 / `acc_array` output) with `pe_ctrl` combinational and control alignment in `top_pe_bas`, and `acc_i` is an external accumulator input. Updated the `primitives.md` status line (all sub-blocks and `top_pe_bas` now built).
- **[Creation]**: Documented [acc_array](./modules/acc_array.md) — the built-and-verified 8-lane accumulator (per lane: window split → tap-level `mux_n` → `cpr_w_n` 3:2 + accumulate `mux_n` → `add_n` → `reg_n`, with a 2-bit fusion carry chained by `gate_n`). Verified end to end (`disp_array → pe_array → acc_array`) across all 11 modes, single-shot and accumulating, with [tb_acc_array](./testbenches/tb_acc_array.md). Added both pages and the `index.md` entries; refreshed the diagram companion `doc/diagrams/acc_array.md`.
- **[Change]**: Renamed `gate_a_n` → [gate_n](./modules/gate_n.md) (generic zero gate / carry enable); in `acc_array` it gates the 2-bit fusion carry at `WIDTH = 2`. Updated the module page, primitives, and `gate_b_n`'s cross-links.
- **[Change]**: [add_n](./modules/add_n.md) reworked — dropped the runtime `is_signed_i`, added a `CARRY`-bit carry-in/out (`{cout_o, out_o} = in_0 + in_1 + cin`), output stays `WIDTH`-bit. Signedness now comes entirely from `acc_array`'s 40-bit tap sign-extension, so the lane adds run unsigned.

## 2026-07-06

- **[Fix]**: BUG-2 — [dp_8](./modules/dp_8.md) carry-save output was not sign-consistent at extreme-operand corners. The final 6:2 `cpr_w_n` used `EXT = 0` (zero guard bits) and truncated to 17 bits, so a sign-extended reduction lost its top carry (resolve still held, sign-consistency did not). Fixed with `FINAL_EXT = 2` → **20-bit** output (16-bit value + 4 guard bits, no truncation). Verified over 5,000,000 corner-biased vectors. See `doc/known_issues.md` (BUG-2).
- **[Update]**: [pe_array](./modules/pe_array.md) — 20-bit DP8 ripples the tree: node widths **28/32/40/40** (every compressor `EXT = 0`; the DP8's 4 guard bits carry through the whole tree), tap widths **18/29/37/38** (each tap = worst-exit value + 2 compressor guard bits). All 11 modes verified sign-consistent under corner-biased operands. Testbenches (`tb_dp_8`, `tb_pe_array`) now bias lanes toward the extremes.
- **[Fix]**: `doc/diagrams/pe_array.md` — corrected the R16R16 modes (8, 9, 12) to `23/27` at L0/L1 (they match R16R8 there — B's high byte enters only at L2), updated the worst-case table and the RTL width/tap paragraph, and fixed the `ext_n` (14) / `reg_n` (2 banks) counts.
- **[Update]**: Restructured the 6 verification pages to Purpose → Parameters → Run → What it checks → How it checks (the last expanded into testbench-quoted `###` subsections describing stimulus, golden model, timing, and compare). Aligned all table pipes across the wiki and joined the `index.md` scope note into a single line (no mid-sentence line breaks).
- **[Update]**: Restructured all 13 module + 2 architecture pages to the fixed section order (Purpose → Parameters → Interface → Instantiation → Internal logic) and expanded every **Internal logic** section into RTL-quoted `###` subsections that walk the datapath for a first-time reader.
- **[Fix]**: [pe_array](./modules/pe_array.md) — corrected the primitive counts (14 `shift_n` / 14 `ext_n`; L3 has neither — it merges two equal-width operands) and kept mode 12's tap at L2 (the `doc/diagrams/pe_array.md` "Bit widths" table still says L3 — stale).
- **[Creation]**: Added the `verification/` folder documenting the six testbenches — [pe_array](./testbenches/tb_pe_array.md), [disp_array](./testbenches/tb_disp_array.md), [dp_8](./testbenches/tb_dp_8.md), [booth_r4](./testbenches/tb_booth_r4.md), [cpr_w_n](./testbenches/tb_cpr_w_n.md), [cpr_c_n](./testbenches/tb_cpr_c_n.md); each links to the DUT it exercises and its `tb/` source.
- **[Update]**: `index.md` — added the Verification section (6 pages) and `verification/` to the folder list; refreshed the scope note (`pe_array` is documented).
- **[Change]**: Removed the `tags` and `timestamp` frontmatter fields from all 15 concept pages (kept `type`/`title`/`description`/`resource`).

## 2026-07-02

- **[Creation]**: Documented [pe_array](./modules/pe_array.md) — built-and-verified 16-DP8 carry-save reduction tree (15 `cpr_w_n` 4:2 + 14 `shift_n` + 15 `ext_n` + L0 `reg_n`; crossed L0 pairs, per-level `<<8`/`<<4`/`<<8`, node widths 25/30/38/39, taps 17/29/37/39). Verified with an integrated `disp_array→pe_array` testbench (11 modes × 2000 random + ramp; golden = `Σ dp8·2^weight` per tap subtree), which passes `-Wall`-clean.
- **[Change]**: `shift_n` and `ext_n` moved `is_signed_i` from a runtime port to a compile-time `IS_SIGNED` parameter (structural-signedness convention, joining `cpr_w_n`); `cpr_w_n`/`cpr_c_n` instantiations updated, re-verified. Updated their module pages, primitives, and `doc/code_style.md`.
- **[Update]**: `index.md` — added `pe_array` to the Architecture section.
- **[Creation]**: Documented [disp_array](./modules/disp_array.md) — built-and-verified operand-dispatch array (8 pairs × MUX A + MUX B + high/low B split + B-gate, from `reg_n`/`mux_n`/`gate_b_n`; data-only, B-gate-only, input-registered). Its per-mode control vectors were extracted from `doc/formulas/modes.xlsx` and drive an 11-mode self-checking testbench, which passes.
- **[Update]**: `index.md` — added the Architecture section (first entry: `disp_array`) and updated the scope note.

## 2026-07-01

- **[Creation]**: Documented the built-and-verified modules — moved each component's design doc from `rtl/<mod>.md` into `modules/` as OKF pages and deleted the originals: [dp_8](./modules/dp_8.md), [booth_r4](./modules/booth_r4.md), [booth_r4_cell](./modules/booth_r4_cell.md), [cpr_w_n](./modules/cpr_w_n.md), [cpr_c_n](./modules/cpr_c_n.md), [fa](./modules/fa.md), [add_n](./modules/add_n.md), [ext_n](./modules/ext_n.md), [shift_n](./modules/shift_n.md), [mux_n](./modules/mux_n.md), [gate_n](./modules/gate_n.md), [gate_b_n](./modules/gate_b_n.md), [reg_n](./modules/reg_n.md).
- **[Update]**: `index.md` — populated the Modules section (13 pages). Higher-level blocks left undocumented (not yet defined).

## 2026-06-30

- **[Creation]**: Initialized the wiki bundle (OKF v0.1) — `index.md` (catalog, declares `okf_version: "0.1"`) and `log.md`, plus empty category folders `architecture/`, `modules/`, `concepts/`, `decisions/`, `experiments/`, `references/`. No concept pages yet.
