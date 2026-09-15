# PE Array (NR4SD BFP) Testbench

## Purpose

`tb_pe_array_nr4sd_bfp` verifies [pe_array_nr4sd_bfp](../modules/pe_array_nr4sd_bfp.md) wired downstream of [disp_array_a](../modules/disp_array_a.md) + [disp_array_b_nr4sd_bfp](../modules/disp_array_b_nr4sd_bfp.md) and the BFP exponent dispatchers, with the baseline [pe_array](../modules/pe_array.md) (fed by the ordinary [disp_array_b](../modules/disp_array_b.md)) alongside as the integer reference. Both B dispatchers see the same operand word and the same controls — **the raw B route is shared** — so the two arrays differ only in how each product is formed: three Booth partial products per lane against the two-digit hybrid (an NR4SD⁺ digit over `{0, +A, +2A, −A}` at weight 1 and a Booth digit at weight 4: the nibble read as signed plus the cross-nibble carry the dispatcher injects).

## Parameters

| Parameter  | Default | Description                         |
| ---------- | ------- | ----------------------------------- |
| `NUM_RAND` | `2000`  | Random `A,B` matrix pairs per mode. |

## Run

```
make sim PROJECT=unified-core TOP_LEVEL=pe_array_nr4sd_bfp
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

| Pass | Exponents                              | Checks                                                                                                                                                                                                                                                                                       |
| ---- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A    | equal (idle DP8s at the minimum scale) | every L1/L2/L3 tap carries the same **value** as the baseline `pe_array`, which itself matches the matmul golden — the L0 taps too, but only in the whole-int4 modes (1, 5); every tap exponent equals the subtree max; the dispatched exponents match the sideband model.                   |
| B    | per-mode legal BFP exponents           | every tap exponent equals the max of the per-DP8 scales over its subtree; every node value at the mode's tap level sits inside the truncation window `[ideal − BLO, ideal + BHI]` of a flat-aligned ideal built from the per-DP8 partials **as the 2-PP hardware forms them**.               |

## How it checks

### Value, not bit pattern

The criterion in pass A is the **resolved value** (sum + carry in the tap width), not the bit pattern that the [tb_pe_array_bfp](./tb_pe_array_bfp.md) bench can demand. NR4SD and Booth spell the same `b` with different digits, so the redundant carry-save encoding legitimately differs while the value it represents does not — the same reasoning as in [tb_pe_array_bpl_b_bfp](./tb_pe_array_bpl_b_bfp.md). The comparison resolves in the tap width: a tap narrower than the node it reads truncates, so at an unread level the true value can exceed the tap and the two encodings then agree only modulo `2^TAP_WIDTH`.

### Why L0 is skipped with a sliced B

With a sliced B every nibble is read as signed, so a lower-nibble DP8 is off by `−16·b₃·A` until L1 recombines it with the nibble above, and its L0 value legitimately differs from the baseline's unsigned read. The L0 comparison is therefore gated to the two modes whose B is a whole int4:

```systemverilog
localparam bit B_INT4 [0:NUM_MODE-1] = '{1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0};

if (B_INT4[mi])
    for (int n = 0; n < NUM_L0; n++)
        if ((b_l0_sum[n] + b_l0_carry[n]) !== (l0_sum[n] + l0_carry[n])) begin
```

Bit-identity becomes legitimate one stage later, at `pe_out`, where the accumulator has resolved the pair — see [tb_acc_array_nr4sd_bfp](./tb_acc_array_nr4sd_bfp.md).

### The ideal follows the hardware

Pass B's per-DP8 golden is not the true dot product but the partial the 2-PP leaf actually forms — every nibble read as signed plus the carry it imports from the gated nibble of the DP8 above it, none into DP8 `4q+3`:

```systemverilog
function automatic longint dp8_gold(input int d);
    ...
    for (int ln = 0; ln < 8; ln++) begin
        av  = is_signed_a[d] ? longint'($signed(a_dp8[d][ln*8 +: 8])) : longint'(a_dp8[d][ln*8 +: 8]);
        cin = 0;
        if (d % 4 != 3)
            cin = (!is_signed_b[d+1] && b_dp8[d+1][ln*4+3]) ? 1 : 0;
        bv  = longint'($signed(b_dp8[d][ln*4 +: 4])) + cin;
        acc = acc + av * bv;
    end
```

So the `±16·b₃·A` terms travel through the aligners of the cascade golden exactly as in the DUT and cancel at L1 — which is what makes the window valid in modes 2 and 6, where unequal exponents inside an L0 node truncate the two terms separately.

### The exponent path is the real RTL

The bench packs the per-block source exponents (4 × 6-bit A word, 4 × 2 × 6-bit B word) and [disp_array_exp_a_bfp](../modules/disp_array_exp_a_bfp.md) / [disp_array_exp_b_bfp](../modules/disp_array_exp_b_bfp.md) dispatch them to the two 6-bit per-DP8 inputs, which the array turns into 7-bit scales. A software sideband model (select by `SEL_A`/`SEL_B`, H/L parity, per-side idle zeroing from the CTR zero codes) runs alongside as the golden: the dispatcher outputs are checked against it every vector, and its 7-bit sums feed the exponent and window goldens of the tree. Pass B draws per-format tie groups, idle-min, and corner-biased deltas around a common base (`±0, 1, 7, 8, 27, 28, 56` or uniform).

### The window

Each `align_cell_bfp` can lose at most 2 LSBs of its node scale, so `BLO` scales with the number of cells in the subtree while `BHI` stays tight. The window is computed from the flat-aligned ideal built out of the per-DP8 partials above — never from a DUT-internal signal.

Result: **11/11 modes PASSED**, 0 mismatches.

Source: [tb_pe_array_nr4sd_bfp.sv](../../tb/tb_pe_array_nr4sd_bfp.sv) — DUT: [pe_array_nr4sd_bfp](../modules/pe_array_nr4sd_bfp.md) (through [disp_array_b_nr4sd_bfp](../modules/disp_array_b_nr4sd_bfp.md); reference: [pe_array](../modules/pe_array.md))
