# PE Grid (BFP) Testbench

## Purpose

`tb_top_NxN_bfp` verifies the BFP grid [top_NxN_bfp](../architectures/top_NxN_bfp.md) at **full pipeline throughput** — a fresh operand into every row/column on **every clock**. Operands are distinct per PE (N independent A matrices, one per row; N independent B, one per column), so PE[r][c] evaluates `A[r] · B[c]` and any wrong row/column fan-out shows up as a mismatch. It is the streaming [tb_top_NxN](./tb_top_NxN.md) extended with the BFP exponent sideband and a distinct-exponent experiment.

## Streaming and the delayed check

Latency `LAT`, streaming check delay `D = LAT − 1`; a ring buffer holds the per-cycle golden so each output is checked against the operand driven `D` cycles earlier, and drain cycles flush the pipeline for the final checks.

## Parameters

| Parameter          | Default | Description                                          |
| ------------------ | ------- | ---------------------------------------------------- |
| `N`                | `2`     | Grid side (kept small — the build is slow).          |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.  |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass. |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_bfp
```

## What it checks

Each of the three streaming patterns — **single-shot**, **accumulate**, **scaling** — runs for every mode with **two exponent experiments** and **three checks**:

| Experiment         | Checks                                                                                                                                                                                                                                                                      |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Equal exponents    | (1, value) every aligner transparent → `out_q` equals the plain matmul golden **bit-for-bit**; every output exponent equals the common scale.                                                                                                                               |
| Distinct exponents | (2, exponents) each PE's output exponent equals the independent `egold` model from its row+col source exponents — **catches fan-out**; (3, mantissa) its output mantissa sits inside the independent cascade window from a software model of dispatch + tree + accumulator. |

Any mismatch is **fatal**.

## Notes

- One A exponent per row and one B exponent per column in the distinct experiment; the mantissa/exponent goldens use **only** the driven operand/exponent words and the per-mode control tables — never a DUT-internal signal — so a fault anywhere in the chain is caught.
- The **accumulate** pattern holds one exponent per PE across its tiles (keeping the window tight and independent); the running-max rescale *across* tiles is covered separately by [tb_acc_array_bfp](./tb_acc_array_bfp.md).
- Same clean reset deassertion as the other grid benches. All 11 modes × 3 streaming passes × 2 exponent experiments, N=2, 0 mismatches, `-Wall` clean.

Source: [tb_top_NxN_bfp.sv](../../tb/tb_top_NxN_bfp.sv) — DUT: [top_NxN_bfp](../architectures/top_NxN_bfp.md)
