# Accumulator Array (Square) Testbench

## Purpose

`tb_acc_array_sqr` is the **whole-path equivalence oracle** for the square variant. It wires the entire square datapath —

```
disp_array_a_sqr / disp_array_b_sqr
   → pe_array_sqr ∥ pe_array_alpha_sqr ∥ pe_array_beta_sqr   (parallel)
   → const_sqr → acc_array_sqr
```

— and checks `pe_out` as a plain matrix multiply, exactly as [tb_acc_array](./tb_acc_array.md) does for the baseline. Because the square path is **bit-exact** to the multiply path, the golden, operand packing and result reconstruction are reused verbatim from `tb_acc_array`; only the DUT and the per-mode controls (square dispatch centering, idle-zero, complex negate, const select) change.

## Parameters

| Parameter  | Default | Description                          |
| ---------- | ------- | ------------------------------------ |
| `NUM_RAND` | `2000`  | Random A,B matrix pairs per mode.    |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=acc_array_sqr
```

## What it checks

| Property           | Check                                                                                    |
| ------------------ | ---------------------------------------------------------------------------------------- |
| Single-shot matmul | `pe_out` (reconstructed per lane / fused pair) equals the golden `X = A·B`, all 11 modes |
| Accumulation       | native-unit seed + `NUM_ACC−1` feedback iterations gives `pe_out == seed + NUM_ACC·X`    |

[acc_array_sqr](../modules/acc_array_sqr.md) applies the exact `÷2`, so `pe_out` is the **true** result and needs no rescale — the reconstruction (`read_result`) is identical to the baseline.

## How it checks

For each mode: build `A`, `B`; fill them corner-biased; compute the golden `X = A·B` (real, or complex with four real products); pack them into the two 256-bit operand words at the Storage-table positions; run the square path; reconstruct each result from its lane (L0) or fused `{H(even), L(odd)}` 40-bit pair (L1..L3) and compare.

The square-specific controls come from the same LUTs the α/β generator testbenches use — `IS_SIGNED_A/B` (dispatch centering + generator removed-operand bias, mode 5 all-signed for idle-clean), `ZERO_I` (idle-zero, modes 5/6), `NEG_I` (`comp_n` block-negate, modes 10/11), `SEL_SHIFT`, `SEL_CONST` — with `SEL_CONST` selecting the const-mux pattern per mode.

### Native-unit seed

`acc_array_sqr` runs the accumulator register in true units (the acc-mux `<<1` doubles the fed-back/seed term, the output `÷2` undoes it). So the seed is loaded in **native units** and the golden is the plain `seed + NUM_ACC·X` — identical to the baseline, no `2×` bookkeeping.

### Mode 12 const

The pass exercises the mode-12 subtlety: C16×C16 is **software pre-negated** (no `comp_n`), so the `im·im` centering does not cancel in `Re` — mode 12's Re uses `c_o` (const-mux pattern `1`), not `c_neg`. Selecting `c_neg` there gives a constant `½·C_real` error on the Re output, which this testbench catches.

Source: [tb_acc_array_sqr.sv](../../tb/tb_acc_array_sqr.sv)
