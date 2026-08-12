# PE Array (Bit-Plane-A BFP)

`pe_array_bpl_a_bfp` — the bit-plane build of [pe_array_bfp](./pe_array_bfp.md): the same 4-level crossed carry-save reduction tree, the same 11 in-tree [align_cell_bfp](./align_cell_bfp.md) sites and the same exponent max-tree, with the 16 DP8 leaves swapped from [dp_8](./dp_8.md) to [dp_8_bpl_a_bfp](./dp_8_bpl_a_bfp.md).

## Purpose

Everything structural is [pe_array_bfp](./pe_array_bfp.md) — the crossed L0 pairing, the `shift_n`/`ext_n` node shape, the single L0 register stage, the aligners at L0/L2/L3 with L1 forwarding only a max, the per-DP8 scale add. This page covers only what the bit-plane leaves change: the **operand contract** and the **widths**.

## What changes at the interface

|                 | `pe_array_bfp`         | `pe_array_bpl_a_bfp`                   |
| --------------- | ---------------------- | ------------------------------------ |
| `b_dp8_i`       | 32 bits — 8 × raw int4 | **40 bits** — 8 × 5-bit exact signed |
| `b_sum_dp8_i`   | —                      | **24 bits** — 4 × 6-bit pair sums    |
| `is_signed_b_i` | present                | **removed**                          |
| `is_signed_a_i` | present                | present                              |

Both B buses come from [disp_array_b_bpl_a_bfp](./disp_array_b_bpl_a_bfp.md), formed once per grid column. `is_signed_b_i` is gone because the dispatcher has already resolved B to signed values; `is_signed_a_i` stays, feeding each DP8's weight-2⁷ correction.

## Parameters

None — fixed to the PE configuration. Identical to [pe_array_bfp](./pe_array_bfp.md) except for the widths the wider DP8 output drives:

| Localparam                    | `pe_array_bfp` | `pe_array_bpl_a_bfp` | Meaning                                     |
| ----------------------------- | -------------- | ------------------ | ------------------------------------------- |
| `DP8_WIDTH`                   | 20             | **22**             | each DP8 carry-save row (sign-consistent).  |
| `SH0`/`SH1`/`SH2`             | 8 / 4 / 8      | 8 / 4 / 8          | per-level left shift (L3 has none).         |
| `L0_EXT`…`L3_EXT`             | 0 / 0 / 0 / 0  | **1 / 1 / 0 / 0**  | guard bits added by each level's `cpr_w_n`. |
| `L0_WIDTH`…`L3_WIDTH`         | 28/32/40/40    | **31/36/44/44**    | internal node width at each level.          |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | 18/29/37/38    | **18/36/40/40**    | tap width exported to the accumulator.      |
| `EXP_IN_WIDTH` / `EXP_WIDTH`  | 6 / 7          | 6 / 7              | dispatched format exponent / product scale. |

The nodes follow `L0 = DP8 + SH0 + L0_EXT`, `L1 = L0 + SH1 + L1_EXT`, `L2 = L1 + SH2 + L2_EXT`, `L3 = L2 + L3_EXT`. The **L1 tap carries its node in full** (36 = 36); L0, L2 and L3 truncate to the accumulator's tap format.

### Why the guard bits reappear

`pe_array_bfp` runs `EXT = 0` at every level — its Booth-derived rows leave enough headroom inside the baseline widths. The bit-plane DP8 delivers a *wider, differently distributed* row, so L0 and L1 each need one guard bit for the compressor to stay sign-consistent (`cpr_w_n` drops any carry out of its top bit). L2 and L3 need none. This is the only structural difference in the tree, and it is what the 22-bit DP8 output was sized for: the free sign-extension pad at the DP8 output plus these two guard bits land the nodes where the 40-bit taps still work.

## Interface

As [pe_array_bfp](./pe_array_bfp.md), with the three changes above:

| Signal                              | Dir | Width   | Description                                                             |
| ----------------------------------- | --- | ------- | ----------------------------------------------------------------------- |
| `clk_i` / `rst_ni`                  | in  | 1       | Clock, asynchronous active-low reset.                                   |
| `a_dp8_i[0:15]`                     | in  | 64 each | A operand per DP8 (8 × int8), from `disp_array_a`.                      |
| `b_dp8_i[0:15]`                     | in  | 40 each | **CHANGED** — B as 8 × 5-bit exact signed values.                       |
| `b_sum_dp8_i[0:15]`                 | in  | 24 each | **NEW** — 4 × 6-bit pairwise B sums.                                    |
| `is_signed_a_i[0:15]`               | in  | 1 each  | Per-DP8 A signedness, from `ctrl` (idle-masked in the grid).            |
| `exp_a_dp8_i` / `exp_b_dp8_i[0:15]` | in  | 6 each  | Per-DP8 format exponents, from the BFP exponent dispatchers.            |
| `sel_shift_i[2:0]`                  | in  | 1 each  | Per-level shift enable: `[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`. |
| `en_level_i[2:0]`                   | in  | 1 each  | Operand-isolation enable per tree branch; masks below the tap.          |
| `l0_sum_o`/`l0_carry_o[0:7]`        | out | 18 each | L0 taps (carry-save), `l0_exp_o` 7-bit alongside.                       |
| `l1_sum_o`/`l1_carry_o[0:3]`        | out | 36 each | **CHANGED** — L1 taps, `l1_exp_o` alongside.                            |
| `l2_sum_o`/`l2_carry_o[0:1]`        | out | 40 each | **CHANGED** — L2 taps, `l2_exp_o` alongside.                            |
| `l3_sum_o`/`l3_carry_o`             | out | 40      | **CHANGED** — L3 tap, `l3_exp_o` alongside.                             |

## Instantiation

```systemverilog
pe_array_bpl_a_bfp pe_array_bpl_a_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .b_dp8_i(b_dp8), .b_sum_dp8_i(b_sum_dp8),
    .is_signed_a_i(is_signed_a),
    .exp_a_dp8_i(exp_a_dp8), .exp_b_dp8_i(exp_b_dp8),
    .sel_shift_i(sel_shift), .en_level_i(en_level),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry), .l0_exp_o(l0_exp),
    .l1_sum_o(l1_sum), .l1_carry_o(l1_carry), .l1_exp_o(l1_exp),
    .l2_sum_o(l2_sum), .l2_carry_o(l2_carry), .l2_exp_o(l2_exp),
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry), .l3_exp_o(l3_exp)
);
```

## Internal logic

The per-DP8 lane slicing gains a third bus — the pair sums are unpacked alongside A and B before the core is instantiated:

```systemverilog
for (ln = 0; ln < NUM_B_SUM; ln++) begin : gen_lane_sum
    assign b_sum_ln[ln] = b_sum_dp8_i[i][ln*SUM_WIDTH +: SUM_WIDTH];
end
dp_8_bpl_a_bfp dp_8_bpl_a_bfp_i (
    .a_i(a_lane), .b_i(b_lane), .b_sum_i(b_sum_ln),
    .is_signed_a_i(is_signed_a_i[i]),
    .sum_o(dp8_sum[i]), .carry_o(dp8_carry[i])
);
```

Everything above the leaves is unchanged — see [pe_array_bfp](./pe_array_bfp.md) for the crossed L0 (`CX0 = 4·(n/2) + n%2`, `CX1 = CX0 + 2`), the aligner placement, the L1 max-forward with [sub_n_bfp](./sub_n_bfp.md) + [mux_n](./mux_n.md), the L0 register bank, and the `en_level_i` isolation.

### A carry-save encoding that differs, and a value that does not

The bit-plane tree reaches the same number through a different reduction, so its redundant carry-save pairs are **not bit-identical** to the baseline's — only the values they represent are. Verification therefore compares resolved tap values, not bit patterns. The exported pair is still sign-consistent at every level, which is all the accumulator needs.

### The idle-DP8 requirement

As in `pe_array_bfp`, an idle DP8 must arrive with **both** exponent sides gated to zero so its scale is the minimum and never wins a downstream max. The bit-plane build adds a second requirement — its `is_signed_a_i` must also be cleared — because with a signed A the weight-2⁷ correction injects a non-zero `+2⁸` constant, and the resulting pair sums to zero *without being zero* (`s ≠ 0`, `c ≠ 0`, `s + c = 0`). A BFP right-shift alignment destroys that cancellation. The grid does the masking; see [top_NxN_bpl_a_bfp](../architectures/top_NxN_bpl_a_bfp.md).

## Verification

[tb_pe_array_bpl_a_bfp](../testbenches/tb_pe_array_bpl_a_bfp.md) runs the array downstream of the real dispatchers with the baseline [pe_array](./pe_array.md) alongside as the integer reference: Pass A (equal exponents) demands every tap carry the same **value** as the baseline while the baseline matches the matmul golden, Pass B (distinct exponents) checks the max-tree exponent exactly and the node value inside the truncation window. All 11 modes, 0 mismatches.

Source: [pe_array_bpl_a_bfp.sv](../../rtl/pe_array_bpl_a_bfp.sv) — Testbench: [tb_pe_array_bpl_a_bfp.sv](../../tb/tb_pe_array_bpl_a_bfp.sv) — Diagram: [pe_array_bpl_a_bfp](../../doc/diagrams/pe_array_bpl_a_bfp.excalidraw)
