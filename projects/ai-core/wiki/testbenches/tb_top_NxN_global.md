# Global 3-Way Equivalence Testbench

## Purpose

`tb_top_NxN_global` is the pre-synthesis equivalence oracle: it instantiates **both** grids — the multiply [top_NxN](../architectures/top_NxN.md) and the square [top_NxN_sqr](../architectures/top_NxN_sqr.md) — in the same bench, drives them with the **exact same inputs on every clock**, and on every check compares **three** results: the golden model, the baseline `out_q`, and the square `out_q`. It proves `golden == baseline == square` for identical inputs, so the two hardware variants are interchangeable.

It is the streaming grid bench ([tb_top_NxN](./tb_top_NxN.md)) with the two DUTs merged in — same tables, packing, golden and three passes, driven at full pipeline throughput (a fresh operand every clock, checked against a pipeline-delayed golden via a ring buffer). Every mismatch reports which relation broke: `BAS!=GOLD`, `SQR!=GOLD`, or `BAS!=SQR`.

## Streaming and the delayed check

Identical scheme to the single-grid benches: latency `LAT = 3` (the same for both grids), streaming check delay `D = LAT − 1 = 2`; a depth-`(LAT+2)` ring buffer holds the per-cycle golden so each output is checked against the operand driven `D` cycles earlier, and `D` zero-operand drain cycles flush the pipeline for the final checks.

## Parameters

| Parameter          | Default | Description                                          |
| ------------------ | ------- | ---------------------------------------------------- |
| `N`                | `2`     | Grid side (kept small — the build is slow).          |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.  |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass. |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_global
```

The build compiles both grids into one binary, so it is slower than a single-grid bench.

## What it checks

Three streaming passes, all 11 modes, with a reset between experiment types. Each PE output is run through `cmp3`, a three-way compare that flags any of `BAS!=GOLD`, `SQR!=GOLD`, `BAS!=SQR`:

| Pass        | Check                                                                                                                            |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Single-shot | `sel_acc=0`, `acc=0`; a fresh operand every cycle, both grids' `out_q(t) == golden(A_(t−D)[r] · B_(t−D)[c])` and each other.     |
| Accumulate  | per-PE seed via `acc`, then stream `NUM_ACC` **distinct** tiles with `sel_acc` feeding back; both `== seed + Σ golden(tile)`.    |
| Scaling     | enable an `nr × nc` rectangle for every `1≤nr,nc≤N` and stream; enabled PEs match golden, **both grids hold disabled PEs at 0**. |

## Notes

- Both DUTs share the exact same `in_a`/`in_b`/`mode`/`sel_acc`/`acc`/`en_row`/`en_col` — the bench drives one set of stimulus wires into both, so any divergence is a real functional difference, not a stimulus mismatch.
- The golden, packing and result reconstruction are the baseline `tb_top_NxN` model unchanged, so `golden == baseline == square` is checked against the identical neutral matmul.
- **Clean reset deassertion** (off the clock edge, `#1` before `rst_ni` rises) is kept — the square grid needs it so a clock-gated square PE holds a clean `0` instead of latching the `½(0−2−2) = −2` pipeline-empty transient. It is harmless for the baseline.
- N=2, all 11 modes × 3 passes, **0 mismatches**, `-Wall` clean.

Source: [tb_top_NxN_global.sv](../../tb/tb_top_NxN_global.sv) — DUTs: [top_NxN](../architectures/top_NxN.md), [top_NxN_sqr](../architectures/top_NxN_sqr.md)
