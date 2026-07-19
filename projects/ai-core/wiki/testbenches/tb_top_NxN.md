# PE Grid Testbench

## Purpose

`tb_top_NxN` verifies the N × N PE grid [top_NxN](../architectures/top_NxN.md) at **full pipeline throughput** — it drives a fresh operand into every row/column on **every clock**, exactly like a real streaming application, and checks each PE's `out_q` against a pipeline-delayed golden. It works through the grid interface only — per-row A, per-col B, shared `mode`/`sel_acc`, per-PE `acc`, and the active-high row/column enables `en_row`/`en_col`. Operands are **distinct per PE**: it draws `N` independent corner-biased A matrices (one per row) and `N` independent B matrices (one per column), so PE[r][c] evaluates `A[r] · B[c]` and any wrong row/column fan-out surfaces as a mismatch. The per-PE golden reuses the mode tables, packing, and result reconstruction of the single-PE testbench (now `top_NxN` at `N = 1`).

## Streaming and the delayed check

The grid latency is `LAT = 3` clocks (disp → pe_array → acc). In a loop that drives an operand and takes **one** `@(posedge)` per iteration, the output seen after iteration `t` belongs to the operand driven at iteration `t − D`, with `D = LAT − 1 = 2` (one edge is shared with the drive). A small ring buffer (`gold_re`/`gold_im`, depth `LAT + 2`) holds the per-cycle golden so each output is checked against the operand that produced it. After the last operand, the loop streams `D` extra zero-operand cycles to drain the pipeline for checking.

## Parameters

| Parameter          | Default | Description                                                               |
| ------------------ | ------- | ------------------------------------------------------------------------- |
| `N`                | `2`     | Grid side; the array is `N × N` PEs (small default keeps the build fast). |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.                       |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass.                      |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass.                      |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN PARAMS="N=2 NUM_STREAM=40 NUM_ACC=8"
```

Larger arrays cost far more to build, so bump `N` deliberately (e.g. `PARAMS="N=8"` for the full chip). Tracing is off by default; add `VCD=1` for a waveform.

## What it checks

| Aspect       | Detail                                                                                                                                             |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fan-out      | distinct A per row, B per col; every PE must equal `golden(A[row] · B[col])`, so a mis-routed operand mismatches                                   |
| Modes        | all 11 (8 real + 3 complex), selected through the shared `mode` (held constant within each streaming burst)                                        |
| Throughput   | a **fresh operand every clock**; the delayed check proves each PE holds the pipeline full without cross-cycle contamination                        |
| Single-shot  | `sel_acc = 0`, `acc = 0`; each PE `out_q(t) == golden(A_(t−D)[r] · B_(t−D)[c])`                                                                    |
| Accumulation | real K-tile matmul — per-PE seed via `acc`, then stream `NUM_ACC` **distinct** tiles with `sel_acc` feeding back; `out_q == seed + Σ golden(tile)` |
| Scaling      | enable every `nr × nc` top-left rectangle (`1 ≤ nr,nc ≤ N`) and stream; enabled PEs track the delayed golden, disabled ones stay held at `0`       |

## How it checks

The tb draws and stores the `N` per-row A and `N` per-col B matrices (`gen_operands`), packs each into its operand word (`pack_a` → `in_a[r]`, `pack_b` → `in_b[c]`), and captures the per-PE golden into the ring buffer for that cycle (`stream_golden`). `stream_check` then compares each PE's `out_q` — read back through the same lane / fused `{H, L}` reconstruction as the single-PE case — against the golden captured `D` cycles earlier; the same task also asserts disabled PEs are held at `0`.

Three streaming passes run in sequence, **with a reset between experiment types**:

1. **Single-shot** — all `en_row`/`en_col` high; drive a fresh operand each cycle with `sel_acc = 0`, and from cycle `t ≥ D` check every PE against the ring golden `t − D`.
2. **Accumulation** — seed each PE via `acc`, then stream `NUM_ACC` **distinct** operand tiles with `sel_acc = 0` on the first (loads `seed + tile₀`) and `1` thereafter (feedback `+ tileₜ`); the golden is summed on the fly. After the tiles, `D` zero-operand drain cycles let exactly `NUM_ACC` tiles settle, then each PE is checked against `seed + Σ golden(tile)`.
3. **Scaling** — for every rectangle `nr × nc` with `1 ≤ nr,nc ≤ N`: reset (so `out_q = 0`), enable the top-left `nr × nc` block via `en_row[rr] = (rr < nr)` and `en_col[cc] = (cc < nc)`, then run the single-shot stream — enabled PEs (`rr < nr && cc < nc`) track the delayed golden while every disabled PE stays `0` (proving the ICG stopped its clock and the operand mask held it).

```systemverilog
for (int rr = 0; rr < NUM_ROW; rr++) en_row[rr] = (rr < nr) ? 1'b1 : 1'b0;
for (int cc = 0; cc < NUM_COL; cc++) en_col[cc] = (cc < nc) ? 1'b1 : 1'b0;
```

Each mode prints `PASS` / `FAIL` per pass; a clean run reports `top_NxN streaming verification: 11/11 single-shot modes passed (0 total mismatches)` with every `acc mode` and `scale mode` also `PASS`.

Source: [tb_top_NxN.sv](../../tb/tb_top_NxN.sv) — DUT: [top_NxN](../architectures/top_NxN.md)
