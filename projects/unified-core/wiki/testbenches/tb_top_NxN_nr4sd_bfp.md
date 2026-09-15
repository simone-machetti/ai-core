# PE Grid (NR4SD BFP) Testbench

## Purpose

`tb_top_NxN_nr4sd_bfp` verifies [top_NxN_nr4sd_bfp](../architectures/top_NxN_nr4sd_bfp.md) as a black box at **full pipeline throughput** — a fresh operand into every row and column on every clock — checking each PE against a pipeline-delayed golden. Operands are **distinct per PE**: N independent A matrices (one per row) and N independent B matrices (one per column), so PE[r][c] evaluates `A[r] · B[c]` and any wrong row/column fan-out shows up as a mismatch. The NR4SD⁺/Booth hybrid recoding, the hoisted recoders and the cross-nibble link are all inside the box: the bench drives the same 256-bit operand and exponent words as [tb_top_NxN_bfp](./tb_top_NxN_bfp.md).

## Parameters

| Parameter          | Default | Description                                          |
| ------------------ | ------- | ---------------------------------------------------- |
| `N`                | `2`     | Grid side — `N × N` PEs (2 for a fast build).        |
| `NUM_STREAM`       | `40`    | Operands streamed per mode in the single-shot pass.  |
| `NUM_ACC`          | `8`     | Distinct tiles accumulated in the accumulation pass. |
| `NUM_STREAM_SCALE` | `10`    | Operands streamed per rectangle in the scaling pass. |

## Run

```
make sim PROJECT=unified-core TOP_LEVEL=top_NxN_nr4sd_bfp
```

`N = 2` by default; `PARAMS="N=<n>"` changes the grid side.

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

### The window follows the 2-PP hardware

The cascade model's per-DP8 partial is the one the hybrid leaf forms — every nibble read as signed plus the carry imported from the gated nibble of the DP8 above, none into DP8 `4q+3` — not the true dot product:

```systemverilog
cin = 0;
if (d % 4 != 3)
    cin = (!IS_SIGNED_B[mi][d+1] && sw_b_dp8[d+1][ln*4+3]) ? 1 : 0;
bv  = longint'($signed(sw_b_dp8[d][ln*4 +: 4])) + cin;
```

The `±16·b₃·A` cross-nibble terms then pass through the model's L0 aligners and cancel at L1 exactly as in the DUT. This matters for the one behavioural caveat of the grid: in **modes 2 and 6 with unequal block exponents** the two terms are truncated on different sides of an L0 node, so the result is no longer bit-identical to the three-partial-product tree (an LSB-level difference, same error bound) — check 3 is a window built on the hardware's own partials, so it neither hides nor mis-flags that difference. With equal exponents check 1 demands bit-identity in every mode, modes 2 and 6 included.

### Scope of the accumulate pattern

The accumulate pattern holds one exponent per PE across its tiles, keeping the accumulate window tight and independent. The running-max rescale **across** tiles is covered separately by [tb_acc_array_nr4sd_bfp](./tb_acc_array_nr4sd_bfp.md), where it can be checked in closed form.

Result: **66/66 PASSED** (3 patterns × 11 modes × 2 experiments), N = 2, 0 mismatches, `-Wall` clean.

## Related

- [tb_top_NxN_nr4sd_bfp_pwr.sv](../../tb/tb_top_NxN_nr4sd_bfp_pwr.sv) — the power-stimulus twin: same mode tables and operand packing, no checking, uniform (not corner-biased) operands, single-shot only with every row and column enabled, dumps `activity.vcd` for post-synthesis power analysis; `+mode=<m>` / `+vectors=<n>` select one mode and the operand count at run time so a per-mode sweep reuses one compiled binary.

Source: [tb_top_NxN_nr4sd_bfp.sv](../../tb/tb_top_NxN_nr4sd_bfp.sv) — DUT: [top_NxN_nr4sd_bfp](../architectures/top_NxN_nr4sd_bfp.md)
