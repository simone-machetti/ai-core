# PE Array (BFP) Testbench

## Purpose

`tb_pe_array_bfp` verifies [pe_array_bfp](../modules/pe_array_bfp.md) driven through the mantissa dispatchers [disp_array_a](../modules/disp_array_a.md) + [disp_array_b](../modules/disp_array_b.md) **and** the BFP exponent dispatchers [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) + [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md), with the baseline [pe_array](../modules/pe_array.md) instantiated **alongside** as the integer reference. Each of the 11 modes is checked both as a plain matrix multiply and against the **BFP contract**.

Every vector runs **twice** — an equal-exponent transparency pass and a distinct-exponent alignment pass — so the tree is proven both bit-identical to the integer path and correct under real per-block scales.

## Parameters

| Parameter  | Default | Description                         |
| ---------- | ------- | ----------------------------------- |
| `NUM_RAND` | `2000`  | Random A,B matrix pairs per mode.   |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_bfp
```

## What it checks

| Pass                       | Check                                                                                                                                                            |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A — equal exponents        | every carry-save tap bus is **bit-identical** to [pe_array](../modules/pe_array.md), which matches the matmul golden; every tap exponent equals the subtree max. |
| B — distinct BFP exponents | every tap exponent equals the max of the per-DP8 scales over its subtree; every node value sits inside the truncation window `[ideal − BLO, ideal + BHI]`.       |

Any mismatch is **fatal**.

## How it checks

### Control vectors

The mode tables carry `SEL_A`/`SEL_B` (block routing), the B-gate ops, and the `CTR` zero codes — the same tables as [tb_disp_array](./tb_disp_array.md). The exponent sideband model (select by `SEL_A`/`SEL_B`, high/low parity, per-side idle-zeroing from the `CTR` codes) runs alongside as the golden and is checked against the dispatcher outputs every vector.

### The golden

For each vector the golden defines `A`, `B`, `X = A·B` (shapes from `modes.xlsx`), fills `A`/`B` with random signed values, packs them into the two 256-bit operand words at the Storage-table byte/nibble positions (so a wrong `SEL` is caught), runs `disp_array → pe_array_bfp`, and compares each golden `X` element against the tap that carries it. **Pass A** draws equal exponents (idle DP8s at the minimum scale) and demands full transparency. **Pass B** draws per-mode legal BFP exponents — per-format tie groups, idle-min, corner-biased deltas around a common base — and checks the max-tree exponent exactly plus a truncation window (each align cell can lose at most 2 LSBs of its node scale, so `BLO` scales with the number of cells in the subtree). The exponent path runs the real RTL end to end: the tb packs the per-block source exponents (4 × 6-bit A word, 4 × 12-bit B word), the exponent dispatchers route them to the two 6-bit per-DP8 inputs, and `pe_array_bfp` forms the 7-bit scales.

### Drive/sample timing

`pe_array_bfp` registers at L0 (and the dispatchers register their input), so each vector is clocked through before the taps are sampled. Operands are corner-biased to stress carry-save sign-consistency at the square-sum boundary.

Source: [tb_pe_array_bfp.sv](../../tb/tb_pe_array_bfp.sv) — DUT: [pe_array_bfp](../modules/pe_array_bfp.md) (through [disp_array_a](../modules/disp_array_a.md) + [disp_array_b](../modules/disp_array_b.md) + [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) / [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md))
