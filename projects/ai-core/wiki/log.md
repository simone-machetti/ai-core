# Log

Change history for the AI-Core wiki — newest first. Entries follow OKF: grouped by ISO-8601 date, each line `**[Action]**: description`.

## 2026-07-02

- **[Creation]**: Documented [disp_array](architecture/disp_array.md) — built-and-verified operand-dispatch array (8 pairs × MUX A + MUX B + high/low B split + B-gate, from `reg_n`/`mux_n`/`gate_b_n`; data-only, B-gate-only, input-registered). Its per-mode control vectors were extracted from `doc/formulas/modes.xlsx` and drive an 11-mode self-checking testbench, which passes.
- **[Update]**: `index.md` — added the Architecture section (first entry: `disp_array`) and updated the scope note.

## 2026-07-01

- **[Creation]**: Documented the built-and-verified modules — moved each component's design doc from `rtl/<mod>.md` into `modules/` as OKF pages and deleted the originals: [dp_8](modules/dp_8.md), [booth_r4](modules/booth_r4.md), [booth_r4_cell](modules/booth_r4_cell.md), [cpr_w_n](modules/cpr_w_n.md), [cpr_c_n](modules/cpr_c_n.md), [fa](modules/fa.md), [add_n](modules/add_n.md), [ext_n](modules/ext_n.md), [shift_n](modules/shift_n.md), [mux_n](modules/mux_n.md), [gate_a_n](modules/gate_a_n.md), [gate_b_n](modules/gate_b_n.md), [reg_n](modules/reg_n.md).
- **[Update]**: `index.md` — populated the Modules section (13 pages). Higher-level blocks left undocumented (not yet defined).

## 2026-06-30

- **[Creation]**: Initialized the wiki bundle (OKF v0.1) — `index.md` (catalog, declares `okf_version: "0.1"`) and `log.md`, plus empty category folders `architecture/`, `modules/`, `concepts/`, `decisions/`, `experiments/`, `references/`. No concept pages yet.
