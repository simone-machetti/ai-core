# PE Array (Bit-Plane-B BFP)

`pe_array_bpl_b_bfp` — the [pe_array_bfp](./pe_array_bfp.md) tree with [dp_8_bpl_b_bfp](./dp_8_bpl_b_bfp.md) leaves. Same 4-level crossed carry-save reduction, same 11 in-tree `align_cell_bfp` aligners, same exponent max-tree, same taps at every level. Only the DP8 cores and their operand contract change.

## Purpose

The tree is deliberately **identical** to [pe_array_bpl_a_bfp](./pe_array_bpl_a_bfp.md) — the two RTL bodies are byte-for-byte the same below the port list. That is what [dp_8_bpl_b_bfp](./dp_8_bpl_b_bfp.md)'s 22-bit output pad buys: both bit-plane builds present the same `DP8_WIDTH`, so both reach nodes 31/36/44/44 and taps 18/36/40/40, and both share one [acc_array_bpl_bfp](./acc_array_bpl_bfp.md).

The consequence is that the whole area difference between the two bit-plane variants sits in the leaves, not the tree:

| section              | baseline-BFP | bit-plane A       | bit-plane B           |
| -------------------- | ------------ | ----------------- | --------------------- |
| DP8 array (16 cores) | 3091.57 µm²  | 2904.80 (−6.0 %)  | **1871.61 (−39.5 %)** |
| CPR tree             | 1698.32 µm²  | 1874.83 (+10.4 %) | 1858.89 (+9.5 %)      |

Both builds pay essentially the same tree penalty — a 22-bit carry-save row instead of 20, plus a guard bit at L0 and L1 — but bit-plane B brings 6.6× the core saving to pay it with. See [Intra-PE Area](../experiments/syn_pe_area.md).

## Parameters

None — fixed to the PE configuration (`EXP_WIDTH = EXP_IN_WIDTH + 1 = 7` holds `e_A + e_B` of two 6-bit format exponents exactly).

| Localparam                 | Value       | Meaning                                        |
| -------------------------- | ----------- | ---------------------------------------------- |
| `NUM_DP8`                  | 16          | Dot-product cores.                             |
| `IN_WIDTH_A` / `SUM_WIDTH` | 9 / 10      | **CHANGED/NEW** — resolved A lanes, pair sums. |
| `IN_WIDTH_B`               | 4           | **CHANGED** — raw int4 B lanes.                |
| `DP8_WIDTH`                | 22          | Carry-save row from each core.                 |
| `SH0` / `SH1` / `SH2`      | 8 / 4 / 8   | Runtime-selected level shifts.                 |
| `L0..L3_WIDTH`             | 31/36/44/44 | Node widths (guard bit at L0 and L1).          |
| `L0..L3_TAP_WIDTH`         | 18/36/40/40 | Exported tap widths.                           |

## Interface

Against [pe_array_bfp](./pe_array_bfp.md), the operand contract changes on two ports and nothing else:

| Signal                                 | Dir | Width          | Description                                                    |
| -------------------------------------- | --- | -------------- | -------------------------------------------------------------- |
| `a_dp8_i[0:15]`                        | in  | 72             | **CHANGED** — 8 × 9-bit exact signed A lanes.                  |
| `a_sum_dp8_i[0:15]`                    | in  | 40             | **NEW** — 4 × 10-bit pairwise A sums.                          |
| `b_dp8_i[0:15]`                        | in  | 32             | **CHANGED** — 8 × 4-bit raw int4 B lanes.                      |
| `is_signed_b_i[0:15]`                  | in  | 1              | Per-DP8 B signedness — feeds each core's weight-2³ correction. |
| `exp_a_dp8_i` / `exp_b_dp8_i`          | in  | 6              | Per-DP8 6-bit format exponents.                                |
| `sel_shift_i` / `en_level_i`           | in  | 3              | Level shift select; per-level register enable.                 |
| `l0..l3_sum_o` / `_carry_o` / `_exp_o` | out | 18/36/40/40, 7 | Carry-save pair + 7-bit scale at every level.                  |

**No `is_signed_a_i`** — resolved in [disp_array_a_bpl_b_bfp](./disp_array_a_bpl_b_bfp.md). This is the exact mirror of the A build, where `is_signed_b_i` is the one that disappears.

## Instantiation

```systemverilog
dp_8_bpl_b_bfp dp_8_bpl_b_bfp_i (
    .a_i          (a_lane),
    .a_sum_i      (a_sum_ln),
    .b_i          (b_lane),
    .is_signed_b_i(is_signed_b_i[i]),
    .sum_o        (dp8_sum[i]),
    .carry_o      (dp8_carry[i])
);
```

## Internal logic

Unchanged from [pe_array_bfp](./pe_array_bfp.md) and [pe_array_bpl_a_bfp](./pe_array_bpl_a_bfp.md): a per-DP8 [add_n](./add_n.md) forms the scale `e_A + e_B` (6 + 6 → 7, exact); the L0 cells consume the crossed pair and emit the L0 node exponents; per L1 node the max of its two L0 exponents is forwarded ([sub_n_bfp](./sub_n_bfp.md) + [mux_n](./mux_n.md), no shifter); L2 and L3 continue the max tree. Every tap exports its exponent next to the carry-save pair, so a tap reads as mantissa pair + scale.

The exponent dispatchers meet only here — A is dispatched per grid **row**, B per grid **column** — and an idle DP8 must arrive with **both** sides gated to zero so its scale is the minimum and never wins a max.

## Verification

[tb_pe_array_bpl_b_bfp](../testbenches/tb_pe_array_bpl_b_bfp.md) runs the array downstream of the real dispatchers with the baseline [pe_array](./pe_array.md) alongside as the integer reference, over 11 modes × two exponent passes. **11/11, 0 mismatches.** As in the A build the criterion is the **resolved tap value**, not the bit pattern: the bit-plane reduction reaches the same number through a different carry-save encoding.

Source: [pe_array_bpl_b_bfp.sv](../../rtl/pe_array_bpl_b_bfp.sv) — Testbench: [tb_pe_array_bpl_b_bfp.sv](../../tb/tb_pe_array_bpl_b_bfp.sv) — Diagram: [pe_array_bpl_b_bfp](../../doc/diagrams/pe_array_bpl_b_bfp.excalidraw)
