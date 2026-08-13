# PE Array (Bit-Plane-B BFP) Testbench

## Purpose

`tb_pe_array_bpl_b_bfp` verifies [pe_array_bpl_b_bfp](../modules/pe_array_bpl_b_bfp.md) wired downstream of [disp_array_a_bpl_b_bfp](../modules/disp_array_a_bpl_b_bfp.md) and the BFP exponent dispatchers, with the baseline [pe_array](../modules/pe_array.md) (fed by the ordinary [disp_array_a](../modules/disp_array_a.md)) alongside as the integer reference. Both dispatchers see the same operand word and the same controls, and **the raw B route is shared**, so the two arrays differ only in how each product is formed.

## Parameters

| Parameter  | Default | Description                         |
| ---------- | ------- | ----------------------------------- |
| `NUM_RAND` | `2000`  | Random `A,B` matrix pairs per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_bpl_b_bfp
```

## What it checks

Each of the 11 modes runs as a plain matrix multiply plus the BFP contract:

1. Define the A, B and X matrices for the mode (shapes from `modes.xlsx`).
2. Fill A and B with random signed values.
3. Compute the golden `X = A · B` (real, or complex with 4 real products).
4. Pack A and B into the two 256-bit operand words at the byte/nibble positions the Storage table assigns — `SEL` only drives routing in the DUT and is never used to place the data, so a wrong `SEL` is caught here.
5. Run `disp_array → pe_array` and read the carry-save taps.
6. Compare each golden X element against the tap that carries it.

Every vector runs twice:

| Pass | Exponents                              | Checks                                                                                                                                                                             |
| ---- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A    | equal (idle DP8s at the minimum scale) | every tap carries the same **value** as the baseline `pe_array`, which itself matches the matmul golden; every tap exponent equals the subtree max.                                |
| B    | per-mode legal BFP exponents           | every tap exponent equals the max of the per-DP8 scales over its subtree; every node value at the mode's tap level sits inside the truncation window `[ideal − BLO, ideal + BHI]`. |

## How it checks

### Value, not bit pattern

The criterion in pass A is the **resolved value** (sum + carry in the tap width), not the bit pattern that the [tb_pe_array_bfp](./tb_pe_array_bfp.md) bench can demand. The bit-plane DP8 reaches the same number through a different reduction, so its redundant carry-save encoding legitimately differs while the value it represents does not. Demanding bit-identity to the Booth tree would be wrong, not merely strict — the same reasoning as in [tb_pe_array_bpl_a_bfp](./tb_pe_array_bpl_a_bfp.md).

### The exponent path is the real RTL

The bench packs the per-block source exponents (4 × 6-bit A word, 4 × 2 × 6-bit B word) and [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) / [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md) dispatch them to the two 6-bit per-DP8 inputs, which the array turns into 7-bit scales. A software sideband model (select by `SEL_A`/`SEL_B`, H/L parity, per-side idle zeroing from the CTR zero codes) runs alongside as the golden: the dispatcher outputs are checked against it every vector, and its 7-bit sums feed the exponent and window goldens of the tree.

### The window

Each `align_cell_bfp` can lose at most 2 LSBs of its node scale, so `BLO` scales with the number of cells in the subtree while `BHI` stays tight. The window is computed from the flat-aligned ideal built out of the per-DP8 golden dot products — never from a DUT-internal signal.

Result: **11/11 modes PASSED**, 0 mismatches.

Source: [tb_pe_array_bpl_b_bfp.sv](../../tb/tb_pe_array_bpl_b_bfp.sv) — DUT: [pe_array_bpl_b_bfp](../modules/pe_array_bpl_b_bfp.md) (reference: [pe_array](../modules/pe_array.md))
