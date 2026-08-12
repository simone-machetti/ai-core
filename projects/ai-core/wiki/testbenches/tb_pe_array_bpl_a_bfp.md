# PE Array (Bit-Plane-A BFP) Testbench

## Purpose

`tb_pe_array_bpl_a_bfp` verifies [pe_array_bpl_a_bfp](../modules/pe_array_bpl_a_bfp.md) wired downstream of [disp_array_b_bpl_a_bfp](../modules/disp_array_b_bpl_a_bfp.md) and the BFP exponent dispatchers, with the baseline [pe_array](../modules/pe_array.md) — fed by the ordinary [disp_array_b](../modules/disp_array_b.md) — instantiated **alongside** as the integer reference.

Both dispatchers see the same operand word and the same controls, so the two arrays differ **only in how each product is formed**. Every vector runs twice, an equal-exponent transparency pass and a distinct-exponent alignment pass.

## Parameters

| Parameter  | Default | Description                       |
| ---------- | ------- | --------------------------------- |
| `NUM_RAND` | `2000`  | Random A,B matrix pairs per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_bpl_a_bfp
```

## What it checks

| Pass                       | Check                                                                                                                                                                              |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A — equal exponents        | every carry-save tap carries the same **value** as [pe_array](../modules/pe_array.md), which itself matches the matmul golden; every tap exponent equals the subtree max.          |
| B — distinct BFP exponents | every tap exponent equals the max of the per-DP8 scales over its subtree; every node value at the mode's tap level sits inside the truncation window `[ideal − BLO, ideal + BHI]`. |

Any mismatch is **fatal**.

## How it checks

### Value, not bit pattern

This is the one place the bit-plane bench must be weaker than [tb_pe_array_bfp](./tb_pe_array_bfp.md), and the reason is structural rather than a relaxation: the bit-plane DP8 reaches the same number through a **different reduction**, so its redundant carry-save encoding legitimately differs from Booth's while the value it represents does not. Pass A therefore compares the resolved value (`sum + carry` in the tap width), not the bit pattern.

Everything else stays strict — the value must match the baseline exactly, on every tap, for every mode.

### The golden

Per vector the bench defines `A`, `B` and `X = A·B` for the mode (shapes from `modes.xlsx`), fills `A`/`B` with random signed values, and packs them into the two 256-bit operand words at the **Storage-table** byte/nibble positions. `SEL` only drives routing in the DUT and is never used to place the data, so a wrong `SEL` is caught. It then runs `disp_array → pe_array` on both paths and compares each golden `X` element against the tap that carries it.

**Pass A** draws equal exponents with idle DP8s at the minimum scale. **Pass B** draws per-mode legal BFP exponents — per-format tie groups, idle-min, corner-biased deltas around a common base — and checks the max-tree exponent exactly plus the truncation window, where `BLO` scales with the number of align cells in the subtree (each can lose at most 2 LSBs of its node scale).

### The exponent path is real RTL

The bench packs the per-block source exponents (4 × 6-bit A word, 4 × 12-bit B word); [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) / [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md) dispatch them to the two 6-bit per-DP8 inputs, and `pe_array_bpl_a_bfp` forms the 7-bit scales. A software sideband model runs alongside as the golden and the dispatcher outputs are checked against it every vector.

Result: **11/11 modes, 0 mismatches**.

Source: [tb_pe_array_bpl_a_bfp.sv](../../tb/tb_pe_array_bpl_a_bfp.sv) — DUT: [pe_array_bpl_a_bfp](../modules/pe_array_bpl_a_bfp.md) (through [disp_array_a](../modules/disp_array_a.md) + [disp_array_b_bpl_a_bfp](../modules/disp_array_b_bpl_a_bfp.md) + the BFP exponent dispatchers; reference [pe_array](../modules/pe_array.md))
