# PE Grid (Square) Testbench

## Purpose

`tb_top_NxN_sqr` verifies the square grid [top_NxN_sqr](../architectures/top_NxN_sqr.md) as a plain matrix multiply at every PE's `out_q`, at **full pipeline throughput** — a fresh operand into every row/column on **every clock**. Because the square grid shares the baseline interface and is **bit-exact** to [top_NxN](../architectures/top_NxN.md), this bench is the [tb_top_NxN](./tb_top_NxN.md) streaming bench reused verbatim — only the DUT changes. Each of the N² PEs is driven distinctly (N independent A matrices, one per row; N independent B, one per column), so PE[r][c] evaluates `A[r] · B[c]` and any wrong row/column fan-out shows up as a mismatch.

Streaming is the stronger check for the square: it proves the shared per-row **−α** and per-column **−β** generator pipelines stay aligned with each PE's product **cycle by cycle** at full throughput, not just for an isolated operand.

## Streaming and the delayed check

Identical scheme to the baseline: latency `LAT = 3`, streaming check delay `D = LAT − 1 = 2`; a depth-`(LAT+2)` ring buffer holds the per-cycle golden so each output is checked against the operand driven `D` cycles earlier, and `D` zero-operand drain cycles flush the pipeline for the final checks.

## Parameters

| Parameter          | Default | Description                                          |
| ------------------ | ------- | ---------------------------------------------------- |
| `N`                | `2`     | Grid side (kept small — the build is slow).          |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.  |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass. |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_sqr
```

## What it checks

Three streaming passes, all 11 modes, with a reset between experiment types:

| Pass        | Check                                                                                                                                              |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Single-shot | `sel_acc=0`, `acc=0`; a fresh operand every cycle, each PE `out_q(t) == golden(A_(t−D)[r] · B_(t−D)[c])`.                                          |
| Accumulate  | per-PE seed via `acc`, then stream `NUM_ACC` **distinct** tiles with `sel_acc` feeding back; `out_q == seed + Σ golden(tile)`.                     |
| Scaling     | enable an `nr × nc` rectangle for every `1≤nr,nc≤N` and stream; enabled PEs track the delayed golden, **disabled PEs stay 0** (clock-gated, held). |

## Notes

- The golden, packing and result reconstruction are the baseline `tb_top_NxN` model unchanged — the two benches differ only in the DUT, the module/`$dumpvars` names, and the display strings, so bas ≡ sqr is checked against the identical neutral matmul.
- **Clean reset deassertion** (off the clock edge) is required: unlike the multiply grid, a clock-gated square PE latches `½(0−2−2) = −2` from the pipeline-empty transient (the α/β generators emit `~0 = −2`) if reset is released *at* a clock edge. Deasserting reset between edges (`#1` before `rst_ni` rises) makes disabled PEs hold their clean `0` — the hold behaviour is otherwise identical to the baseline. Both benches keep this deassertion so they stay byte-identical apart from the DUT.

Source: [tb_top_NxN_sqr.sv](../../tb/tb_top_NxN_sqr.sv)
