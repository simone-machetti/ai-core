# Global 3-Way Equivalence Testbench

## Purpose

`tb_top_NxN_global` is the pre-synthesis equivalence oracle: it instantiates **both** BFP grids — [top_NxN_bfp](../architectures/top_NxN_bfp.md) and the bit-plane [top_NxN_bpl_b_bfp](../architectures/top_NxN_bpl_b_bfp.md) — in the same bench, drives them with the **exact same inputs on every clock**, and on every check compares **three** results: the golden model, the baseline-BFP `out_q`, and the bit-plane-B `out_q`. It proves `golden == baseline-BFP == bit-plane-B` for identical inputs.

This closes the one gap the per-variant benches leave. Each of those checks its own variant against the plain **integer** baseline, so equivalence between the two BFP grids was only ever *transitive*. Here they are compared directly, RTL against RTL, on identical stimulus.

It is the streaming grid bench ([tb_top_NxN](./tb_top_NxN.md)) with the two DUTs merged in — same tables, packing and golden, driven at full pipeline throughput (a fresh operand every clock, checked against a pipeline-delayed golden via a ring buffer). Every mismatch reports which relation broke: `BFP!=GOLD`, `BPL!=GOLD`, or `BFP!=BPL`.

## Parameters

| Parameter          | Default | Description                                            |
| ------------------ | ------- | ------------------------------------------------------ |
| `N`                | `2`     | Grid side (kept small — the build compiles two grids). |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.    |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass.   |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass.   |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_global
```

## What it checks

Four passes, all 11 modes, with a reset between experiment types. Each PE output goes through `cmp3`, the three-way compare:

| Pass            | Exponents | Check                                                                                                                            |
| --------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------- |
| 1. Single-shot  | equal     | `sel_acc=0`, `acc=0`; a fresh operand every cycle, both grids' `out_q(t) == golden(A_(t−D)[r] · B_(t−D)[c])` and each other.     |
| 2. Accumulate   | equal     | per-PE seed via `acc`, then stream `NUM_ACC` **distinct** tiles with `sel_acc` feeding back; both `== seed + Σ golden(tile)`.    |
| 3. Scaling      | equal     | enable an `nr × nc` rectangle for every `1≤nr,nc≤N` and stream; enabled PEs match golden, **both grids hold disabled PEs at 0**. |
| 4. Distinct-exp | random    | no plain-matmul golden — the two grids are compared **directly against each other** and the divergence measured.                 |

In passes 1–3 every 6-bit exponent field carries the same `EXP_VAL`, so every BFP aligner is bit-transparent and both grids must reproduce the plain integer matmul exactly; each PE's `out_exp` must equal the common product scale `2 × EXP_VAL` on both grids.

## How it checks

### Why pass 4 exists, and what it can and cannot prove

With equal exponents the aligners never shift, so passes 1–3 exercise the mantissa datapath but leave the *truncating* right shift untested. Pass 4 drives random distinct exponents — one per row for A, one per column for B, varied per block — so the aligners really shift.

There is no matmul golden available there, because alignment truncates. Instead the two grids are compared to each other, and the bench reports **results compared, results differing, max |bfp − bpl| in LSBs**, plus a **VALIDITY** line counting how many results were actually altered by alignment — if that count is zero the scan proves nothing and says so.

The shift *amounts* are identical by construction: the exponent logic is untouched between the two variants and is data-independent. What pass 4 measures is whether the two different **carry-save encodings** survive the truncating right shift identically.

### The measured result

They do not, quite — and that is expected rather than a fault. At random exponents **12 of 5120** results differ, by at most **16 LSB**, with **0** exponent mismatches. Both encodings represent the same value, but `align_cell_bfp` truncates *per row*, so two encodings of one number can lose different amounts. Both results still lie inside the window `[gv − gd − 1, gv]` that each variant's own bench already verifies against, so `|bfp − bpl| ≤ gd + 1` holds by construction — the divergence is bounded by the same truncation window both designs are specified to, not a new source of error.

Passes 1–3 are **bit-exact**: 33/33 (3 passes × 11 modes), 0 mismatches.

## Notes

- Both DUTs share the exact same `in_a`/`in_b`/`in_exp_a`/`in_exp_b`/`mode`/`sel_acc`/`acc`/`acc_exp`/`en_row`/`en_col` — the bench drives one set of stimulus wires into both, so any divergence is a real functional difference, not a stimulus mismatch.
- Latency `LAT` is identical for both grids; streaming check delay `D = LAT − 1`, with a ring buffer holding the per-cycle golden and `D` drain cycles flushing the pipeline for the final checks.
- Operands are corner-biased and distinct per PE (N independent A matrices per row, N independent B per column), so a wrong row/column fan-out shows up as a mismatch.
- The build compiles both grids into one binary, so it is slower than a single-grid bench.

Source: [tb_top_NxN_global.sv](../../tb/tb_top_NxN_global.sv) — DUTs: [top_NxN_bfp](../architectures/top_NxN_bfp.md), [top_NxN_bpl_b_bfp](../architectures/top_NxN_bpl_b_bfp.md)
