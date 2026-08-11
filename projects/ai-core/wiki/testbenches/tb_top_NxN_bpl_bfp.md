# PE Grid (Bit-Plane BFP) Testbench

## Purpose

`tb_top_NxN_bpl_bfp` drives [top_NxN_bpl_bfp](../architectures/top_NxN_bpl_bfp.md) as a black box at **full pipeline throughput** — a fresh operand into every row and column on every clock, each PE checked against a pipeline-delayed golden held in a ring buffer. Operands are distinct per PE (N independent A matrices, one per row; N independent B matrices, one per column), so PE[r][c] evaluates `A[r] · B[c]` and any wrong row/column fan-out shows up as a mismatch.

Structurally the bit-plane counterpart of [tb_top_NxN_bfp](./tb_top_NxN_bfp.md), with the same three streaming patterns, two exponent experiments and three checks.

## Parameters

| Parameter          | Default | Description                                          |
| ------------------ | ------- | ---------------------------------------------------- |
| `N`                | `2`     | Grid side — `N × N` PEs (2 keeps the build fast).    |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.  |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass. |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_bpl_bfp
```

## What it checks

Each of the three streaming patterns — **single-shot**, **accumulate**, **rectangle scaling** via `en_row`/`en_col` — runs for every mode with two exponent experiments:

| Experiment                                                   | Checks                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Equal exponents                                              | `out_q` equals the plain matmul golden **bit-for-bit** (every aligner transparent), and every output exponent equals the common scale.                                                                                                                  |
| Distinct exponents (one per row for A, one per column for B) | each PE's output exponent equals an independent `egold` model built from its row + column source exponents (catches fan-out), and its output mantissa sits inside an independent cascade window from a software model of dispatch + tree + accumulator. |

The mantissa and exponent goldens use **only** the driven operand/exponent words and the per-mode control tables — never a DUT-internal signal — so a fault anywhere in the chain is caught. Any mismatch is **fatal**.

## How it checks

### Throughput and latency

A fresh operand is driven every clock; the output at iteration `t` belongs to the operand driven at `t − D` (`D = LAT − 1`). A ring buffer of per-cycle goldens supplies the comparison, so the grid is verified under continuous back-to-back operation rather than one settled vector at a time.

### The accumulate pattern

One exponent is held per PE across its tiles, which keeps the accumulate window tight and independent — the running-max rescale *across* tiles is covered separately by [tb_acc_array_bpl_bfp](./tb_acc_array_bpl_bfp.md).

Result: **66/66** (mode × pattern × experiment), N = 2, **0 mismatches**, `-Wall` clean.

## Power stimulus

[tb_top_NxN_bpl_bfp_pwr.sv](../../tb/tb_top_NxN_bpl_bfp_pwr.sv) is the companion stimulus bench for the power experiments — it drives activity and checks nothing, producing the `activity.vcd` that [Synthesis Power](../experiments/syn_pwr.md) and [Per-Mode Synthesis Power](../experiments/syn_mode_pwr.md) annotate. Uniform independent operands, no reuse, no sparsity, single-shot only: an **upper bound** on dynamic power, not a typical-workload figure. `+mode=<m>` and `+vectors=<n>` are read at run time so a mode sweep reuses one compiled binary.

Source: [tb_top_NxN_bpl_bfp.sv](../../tb/tb_top_NxN_bpl_bfp.sv) — DUT: [top_NxN_bpl_bfp](../architectures/top_NxN_bpl_bfp.md)
