# PE Grid (Bit-Plane-B BFP) Testbench

## Purpose

`tb_top_NxN_bpl_b_bfp` verifies [top_NxN_bpl_b_bfp](../architectures/top_NxN_bpl_b_bfp.md) as a black box at **full pipeline throughput** — a fresh operand into every row and column on every clock — checking each PE against a pipeline-delayed golden. Operands are **distinct per PE**: N independent A matrices (one per row) and N independent B matrices (one per column), so PE[r][c] evaluates `A[r] · B[c]` and any wrong row/column fan-out shows up as a mismatch.

## Parameters

| Parameter          | Default | Description                                          |
| ------------------ | ------- | ---------------------------------------------------- |
| `N`                | `2`     | Grid side — `N × N` PEs (2 for a fast build).        |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.  |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass. |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_bpl_b_bfp
```

## What it checks

Three streaming patterns × 11 modes × **two exponent experiments** and **three checks**:

| Pattern     | What it exercises                                          |
| ----------- | ---------------------------------------------------------- |
| single-shot | back-to-back independent operands at max throughput.       |
| accumulate  | `NUM_ACC` tiles into each PE's accumulator.                |
| scaling     | every `rows × cols` rectangle via `en_row_i` / `en_col_i`. |

| Experiment         | Checks                                                                                                                                                                                                                                                                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| equal exponents    | **(1, value)** `out_q` equals the plain matmul golden bit-for-bit; every output exponent equals the common scale.                                                                                                                                                                              |
| distinct exponents | **(2, exponents)** each PE's output exponent equals the independent `egold` model from its row + column source exponents — this is the fan-out check; **(3, mantissa)** the output mantissa sits inside the independent cascade window from a software model of dispatch + tree + accumulator. |

The mantissa and exponent goldens use only the driven operand/exponent words and the per-mode control tables — **never a DUT-internal signal** — so a fault anywhere in the chain is caught.

## How it checks

### Pipeline-delayed comparison

The output at iteration `t` belongs to the operand driven at `t − D`, `D = LAT − 1`; a ring buffer holds the per-cycle golden. This is what lets the bench run at full throughput instead of one-operand-at-a-time, which is the regime where a fan-out or pipeline-alignment fault actually shows.

### Scope of the accumulate pattern

The accumulate pattern holds one exponent per PE across its tiles, keeping the accumulate window tight and independent. The running-max rescale **across** tiles is covered separately by [tb_acc_array_bpl_b_bfp](./tb_acc_array_bpl_b_bfp.md), where it can be checked in closed form.

Result: **66/66 PASSED** (3 patterns × 11 modes × 2 experiments), N = 2, 0 mismatches, `-Wall` clean.

## Related

- [tb_top_NxN_bpl_b_bfp_pwr.sv](../../tb/tb_top_NxN_bpl_b_bfp_pwr.sv) — the power-stimulus twin: same mode tables and operand packing, no checking, uniform (not corner-biased) operands, dumps `activity.vcd` for post-synthesis power analysis.
- [tb_top_NxN_global](./tb_top_NxN_global.md) — instantiates this grid **next to** [top_NxN_bfp](../architectures/top_NxN_bfp.md) in one bench for a direct RTL-vs-RTL equivalence.

Source: [tb_top_NxN_bpl_b_bfp.sv](../../tb/tb_top_NxN_bpl_b_bfp.sv) — DUT: [top_NxN_bpl_b_bfp](../architectures/top_NxN_bpl_b_bfp.md)
