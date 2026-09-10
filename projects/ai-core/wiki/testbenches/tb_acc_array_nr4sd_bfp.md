# Accumulator Array (NR4SD BFP) Testbench

## Purpose

`tb_acc_array_nr4sd_bfp` verifies the **full NR4SD BFP PE datapath** — [pe_array_nr4sd_bfp](../modules/pe_array_nr4sd_bfp.md) → [acc_array_bfp](../modules/acc_array_bfp.md) — with the integer datapath ([pe_array](../modules/pe_array.md) → [acc_array](../modules/acc_array.md)) alongside as reference. The mantissa dispatchers feed both (the raw B route through [disp_array_b](../modules/disp_array_b.md), the recoded one through [disp_array_b_nr4sd_bfp](../modules/disp_array_b_nr4sd_bfp.md)); the exponent dispatchers feed the BFP tree and accumulator. `acc_array_bfp` is **reused unchanged**: the NR4SD DP8 keeps `DP8_WIDTH` at 20, so the tap widths are baseline-BFP's exactly and there is no `acc_array_nr4sd_bfp` to test.

## Parameters

| Parameter  | Default | Description                          |
| ---------- | ------- | ------------------------------------ |
| `NUM_RAND` | `2000`  | Random `A,B` matrix pairs per mode.  |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_nr4sd_bfp TB=tb_acc_array_nr4sd_bfp
```

## What it checks

Every mode runs twice per vector:

| Pass | Exponents                         | Checks                                                                                                                                                                                                                                                                                                                 |
| ---- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A    | equal                             | every BFP aligner is bit-transparent, so the BFP output is **bit-identical** to the baseline at `pe_out` — single-shot and through the seed + `NUM_ACC−1` feedback accumulation — while the baseline itself matches the matmul golden (`seed + NUM_ACC × result`); every accumulator exponent equals the common scale. |
| B    | per-mode BFP, seed at min scale 0 | the running accumulator scale equals the tap scale, and the accumulator value is exactly `(seed >>> tap_exp) + NUM_ACC × tap`, read directly from the BFP tap.                                                                                                                                                         |

Any mismatch is **fatal**.

## How it checks

### Why pass A can demand bit-identity here

At the tap level [tb_pe_array_nr4sd_bfp](./tb_pe_array_nr4sd_bfp.md) can only compare resolved *values*, because NR4SD and Booth reach the same number through different carry-save encodings — and it cannot compare L0 at all with a sliced B, where a lower-nibble DP8 is off by `−16·b₃·A` until L1 recombines it. By `pe_out` both objections are gone: the accumulator has **resolved** the carry-save pair into a single word, and every tap a sliced-B mode reads sits at L1 or above (the only L0 reader, mode 1, multiplies whole int4 B). So the stronger bit-identity check applies, single-shot and across the feedback loop.

### Why pass B is exact rather than a window

A min-scale seed floors **once** on the first alignment, and every later feedback add sits at the stable tap scale. That makes the closed form exact rather than bounded — a bit-exact check of the in-loop alignment and the running-max exponent, with no window to hide a small error:

```systemverilog
function automatic longint seed_floor(input longint v, input int e);
    return v >>> ((e > 63) ? 63 : e);
endfunction

etap = egold(lvl, rn);
gexp = seed_floor(acc_seed[o], int'(etap)) + NUM_ACC * resolve_tap_bfp(lvl, rn);
if (read_result_bfp(lvl, rn) !== gexp) begin
```

The tap on the right-hand side is the DUT's own BFP tap, resolved in the tap width — so pass B proves the accumulator against what the tree delivered, while the tree itself is proven by the PE-array bench.

Result: **11/11 modes PASSED** — Pass-A single-shot, Pass-A accumulation and Pass-B min-scale seed — 0 mismatches.

Source: [tb_acc_array_nr4sd_bfp.sv](../../tb/tb_acc_array_nr4sd_bfp.sv) — DUTs: [pe_array_nr4sd_bfp](../modules/pe_array_nr4sd_bfp.md), [acc_array_bfp](../modules/acc_array_bfp.md)
