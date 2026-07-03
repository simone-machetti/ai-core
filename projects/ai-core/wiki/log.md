# Log

Change history for the AI-Core wiki — newest first. Entries follow OKF: grouped by ISO-8601 date, each line `**[Action]**: description`.

## 2026-07-02

- **[Creation]**: Documented [pe_array](architecture/pe_array.md) — built-and-verified 16-DP8 carry-save reduction tree (15 `cpr_w_n` 4:2 + 14 `shift_n` + 15 `ext_n` + L0 `reg_n`; crossed L0 pairs, per-level `<<8`/`<<4`/`<<8`, node widths 25/30/38/39, taps 17/29/37/39). Verified with an integrated `disp_array→pe_array` testbench (11 modes × 2000 random + ramp; golden = `Σ dp8·2^weight` per tap subtree), which passes `-Wall`-clean.
- **[Change]**: `shift_n` and `ext_n` moved `is_signed_i` from a runtime port to a compile-time `IS_SIGNED` parameter (structural-signedness convention, joining `cpr_w_n`); `cpr_w_n`/`cpr_c_n` instantiations updated, re-verified. Updated their module pages, [primitives](../doc/diagrams/primitives.md), and `doc/code_style.md`.
- **[Update]**: `index.md` — added `pe_array` to the Architecture section.
- **[Creation]**: Documented [disp_array](architecture/disp_array.md) — built-and-verified operand-dispatch array (8 pairs × MUX A + MUX B + high/low B split + B-gate, from `reg_n`/`mux_n`/`gate_b_n`; data-only, B-gate-only, input-registered). Its per-mode control vectors were extracted from `doc/formulas/modes.xlsx` and drive an 11-mode self-checking testbench, which passes.
- **[Update]**: `index.md` — added the Architecture section (first entry: `disp_array`) and updated the scope note.

## 2026-07-01

- **[Creation]**: Documented the built-and-verified modules — moved each component's design doc from `rtl/<mod>.md` into `modules/` as OKF pages and deleted the originals: [dp_8](modules/dp_8.md), [booth_r4](modules/booth_r4.md), [booth_r4_cell](modules/booth_r4_cell.md), [cpr_w_n](modules/cpr_w_n.md), [cpr_c_n](modules/cpr_c_n.md), [fa](modules/fa.md), [add_n](modules/add_n.md), [ext_n](modules/ext_n.md), [shift_n](modules/shift_n.md), [mux_n](modules/mux_n.md), [gate_a_n](modules/gate_a_n.md), [gate_b_n](modules/gate_b_n.md), [reg_n](modules/reg_n.md).
- **[Update]**: `index.md` — populated the Modules section (13 pages). Higher-level blocks left undocumented (not yet defined).

## 2026-06-30

- **[Creation]**: Initialized the wiki bundle (OKF v0.1) — `index.md` (catalog, declares `okf_version: "0.1"`) and `log.md`, plus empty category folders `architecture/`, `modules/`, `concepts/`, `decisions/`, `experiments/`, `references/`. No concept pages yet.
