# PE Grid (Square-BFP) Testbench

## Purpose

`tb_top_NxN_sqr_bfp` verifies the square-BFP grid [top_NxN_sqr_bfp](../architectures/top_NxN_sqr_bfp.md) at **full pipeline throughput** — a fresh operand into every row/column on **every clock**, distinct per PE (N A matrices per row, N B per column), so PE[r][c] evaluates `A[r] · B[c]`. Externally the square PE is a **black box** that computes `A · B` in block floating point via the square identity, so it is verified exactly like [tb_top_NxN_bfp](./tb_top_NxN_bfp.md).

## Streaming and the delayed check

Latency `LAT`, streaming check delay `D = LAT − 1`; a ring buffer holds the per-cycle golden so each output is checked against the operand driven `D` cycles earlier, with drain cycles flushing the pipeline.

## Parameters

| Parameter          | Default | Description                                          |
| ------------------ | ------- | ---------------------------------------------------- |
| `N`                | `2`     | Grid side (kept small — the build is slow).          |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.  |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass. |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp
```

## What it checks

Each of the three streaming patterns — **single-shot**, **accumulate**, **scaling** — runs for every mode with **two exponent experiments**:

| Experiment         | Check                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Equal exponents    | every aligner transparent and the square identity exact → `out_q` equals the plain matmul golden **bit-for-bit**; every output exponent equals the common scale `2·base`. This black-box check exercises the whole grid: row/col fan-out, per-PE accumulate, streaming, clock-gating / scaling, [const_sqr_bfp](../modules/const_sqr_bfp.md), and the full mantissa datapath with the aligners transparent. |
| Distinct exponents | each PE's output exponent equals the independent `egold` model (catches exponent fan-out and the max-tree); its output mantissa sits inside the independent square-datapath window.                                                                                                                                                                                                                         |

Any mismatch is **fatal**.

## Notes

- The distinct-exponent **window reuses the multiply software model** (`dispatch` / `dp8_gold`): the square places the *same* operands into the *same* DP8s (only centered, with the L0 [comp_n](../modules/comp_n.md) block-negate reproducing the sign the multiply bakes into its dispatch), and centering + α/β/C cancel, so each DP8 bundle resolves to exactly `2×` the signed product. Two square changes: L0 feeds `2·dp8_gold`, and its truncation slack is per **7-row** bundle `{PE, −α, −β, C}` (up to 6 LSBs lost per aligned bundle vs 1 for the multiply's 2-row DP8); the `½` then halves the window at read time.
- The goldens use **only** the driven operand/exponent words and the per-mode control tables — never a DUT-internal signal. The **accumulate** pattern holds one exponent per PE across its tiles; the running-max rescale across tiles is covered by [tb_acc_array_bfp](./tb_acc_array_bfp.md).
- All 11 modes × 3 streaming passes × 2 exponent experiments (**66/66**), N=2, 0 mismatches, `-Wall` clean.

Source: [tb_top_NxN_sqr_bfp.sv](../../tb/tb_top_NxN_sqr_bfp.sv) — DUT: [top_NxN_sqr_bfp](../architectures/top_NxN_sqr_bfp.md)
