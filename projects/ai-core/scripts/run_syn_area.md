# Per-module Area Synthesis — Baseline 8x8 vs Square 8×8

Module-area experiment for the `top_NxN` (baseline) vs `top_NxN_sqr` (square) 8×8
comparison. Each leaf/periphery component is synthesized **once** with the shared
Yosys + ASAP7 flow; the two 8×8 areas are then assembled **analytically** from the
per-module cell areas × their instance counts. Hierarchy is preserved (the PE is the
replicated tile), which mirrors the intended hierarchical place-and-route — a full
monolithic flatten is neither realizable as a tiled array nor representative of the
eventual floorplan. Interconnect, clock tree and placement utilization are **out of
scope here** and come later from P&R.

Output is **cell area** (ASAP7, `stat -hierarchy` with the RVT/TT liberty). The
deliverable is the **baseline vs square ratio**, not absolute µm².

## Flow

```
make syn PROJECT=ai-core TOP_LEVEL=<module> OUT_DIR=<module>
```

- Area report: `projects/ai-core/imp/<module>/report/area.rpt` (rolled-up cell area of `<module>` and its submodules).
- Library: `asap7sc7p5t` RVT TT (`dfflibmap` for sequential, `abc` for combinational).
- A distinct `OUT_DIR` per module keeps reports from clobbering each other.
- All listed components have `localparam`-only interfaces, so no `-G` overrides are needed.

## Baseline `top_NxN` (N=8) — synthesize these

| Component      | ×count (8×8) | reg_n inst | flops incl. | Captures / notes                                                                          |
| -------------- | ------------ | ---------- | ----------- | ----------------------------------------------------------------------------------------- |
| `ctrl`         | 1            | 4          | 9           | mode(4) + sel_shift_hi(2) + sel_out(2) + prop_carry(1)                                    |
| `disp_array_a` | 8            | 1          | 256         | stage-1 A input reg (64×4)                                                                |
| `disp_array_b` | 8            | 1          | 256         | stage-1 B input reg (64×4)                                                                |
| `pe`           | 64           | 5          | 928         | pe_array (448) + acc_array (160) + 2 acc-pipe regs (320) + operand isolation (16×96 AND2) |

Top-level registers (no component home): `sel_acc` pipeline = **2 flops** — account as flops × unit-DFF area.

## Square `top_NxN_sqr` (N=8) — synthesize these

| Component            | ×count (8×8) | reg_n inst | flops incl. | Captures / notes                                                                                                      |
| -------------------- | ------------ | ---------- | ----------- | --------------------------------------------------------------------------------------------------------------------- |
| `ctrl_sqr`           | 1            | 5          | 11          | mode(4) + sel_shift_hi(2) + sel_out(2) + sel_const(2) + prop_carry(1)                                                 |
| `const_sqr`          | 1            | 0          | 0           | pure combinational LUT                                                                                                |
| `disp_array_a_sqr`   | 8            | 1          | 256         | stage-1 A input reg (64×4)                                                                                            |
| `disp_array_b_sqr`   | 8            | 1          | 256         | stage-1 B input reg (64×4)                                                                                            |
| `pe_array_alpha_sqr` | 8            | 2          | 416         | per-**row** α generator, L0 reg (26×8 ×2)                                                                             |
| `pe_array_beta_sqr`  | 8            | 2          | 416         | per-**col** β generator, L0 reg (26×8 ×2)                                                                             |
| `pe_sqr`             | 64           | 5          | 896         | pe_array_sqr (416) + acc_array_sqr (160) + 2 acc-pipe regs (320) + operand isolation (dp8 **+ α/β taps**, ≈3084 AND2) |

Top-level registers (no component home): `sel_acc` (2) + const pipeline `mode`(4)+`c`(32)+`c_neg`(8) = **46 flops** — account as flops × unit-DFF area.

## ICG cells — excluded from the analysis

Both grids instantiate **80 `icg`** cells: 64 per-PE + 8 per-row + 8 per-column.
The count is **identical** on both sides. ASAP7 (this tech lib) has **no dedicated
ICG cell**, so `icg` is excluded from the area sum on both sides — dropping an equal,
identical term leaves the baseline-vs-square comparison fair.

## 8×8 assembly

```
A_bas = 1·A(ctrl) + 8·A(disp_array_a) + 8·A(disp_array_b) + 64·A(pe) + 2·A_dff
A_sqr = 1·A(ctrl_sqr) + 1·A(const_sqr) + 8·A(disp_array_a_sqr) + 8·A(disp_array_b_sqr)
        + 8·A(pe_array_alpha_sqr) + 8·A(pe_array_beta_sqr) + 64·A(pe_sqr) + 46·A_dff
```

`A_dff` = unit DFF cell area from the ASAP7 SEQ liberty. ICG excluded from both.
