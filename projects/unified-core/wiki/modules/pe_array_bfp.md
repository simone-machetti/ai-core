# PE Array (BFP)

`pe_array_bfp` — the BFP variant of [pe_array](./pe_array.md). Same 16 [dp_8](./dp_8.md) cores and same 4-level crossed carry-save reduction tree (8 → 4 → 2 → 1), but every merge that can combine differently-scaled partials gains an [align_cell_bfp](./align_cell_bfp.md), and the tree carries an **exponent sideband** next to each carry-save tap. With all exponents equal every aligner is bit-transparent, so the BFP path is bit-identical to the plain-integer [pe_array](./pe_array.md).

## Purpose

BFP is a pure exponent sideband on top of the integer datapath. The mantissa tree is unchanged — same 16 `dp_8` (signed per DP8, as the baseline), same crossed L0 pairing, same `shift_n`/`ext_n`/`cpr_w_n` node shape, same widths, same single L0 register stage, same tap slicing. This page covers only the two deltas; see [pe_array](./pe_array.md) for the shared tree anatomy.

1. **In-tree alignment.** One [align_cell_bfp](./align_cell_bfp.md) sits before the CPR 4:2 of every **L0, L2 and L3** node (8 + 2 + 1 = 11 sites), placed *after* the radix `shift_n`/`ext_n` on the width-matched CPR operands. It brings the node's two carry-save addends to their common scale `max(e_left, e_right)`, the smaller-exponent side arithmetic-right-shifted (truncating), before they compress. **L1 never aligns** — see [Why L1 only forwards a max](#why-l1-only-forwards-a-max).
2. **The exponent path.** `exp_a_dp8_i` / `exp_b_dp8_i` bring the dispatched per-DP8 6-bit format exponents; one [add_n](./add_n.md) per DP8 forms the product scale `e_A + e_B`, and a running max tree carries a scale alongside every tap.

Because an aligned addend is only a **right-shifted (smaller)** version of its integer worst case, no node, tap or guard bit grows: every width is exactly [pe_array](./pe_array.md)'s. The integer modes run through with alignment amount 0 — bit-exact.

## Parameters

None — fixed to the PE configuration; the shape is baked in as `localparam`s. Identical to [pe_array](./pe_array.md) plus the two exponent widths:

| Localparam                    | Value             | Meaning                                                                 |
| ----------------------------- | ----------------- | ----------------------------------------------------------------------- |
| `NUM_DP8`                     | 16                | `dp_8` cores driving the tree.                                          |
| `NUM_L0`/`NUM_L1`/`NUM_L2`    | 8 / 4 / 2         | node count at L0/L1/L2 (L3 is a single node).                           |
| `DP8_WIDTH`                   | 20                | each `dp_8` carry-save row width (sign-consistent).                     |
| `SH0`/`SH1`/`SH2`             | 8 / 4 / 8         | per-level left-shift amount (L0/L1/L2; L3 has no shift).                |
| `L0_WIDTH`…`L3_WIDTH`         | 28 / 32 / 40 / 40 | internal node width at each level (what feeds the next level).          |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | 18 / 29 / 37 / 38 | tap width exported to the accumulator at each level.                    |
| `EXP_IN_WIDTH`                | 6                 | **NEW** — dispatched per-DP8 format-exponent width.                     |
| `EXP_WIDTH`                   | 7                 | **NEW** — product-domain scale width (`e_A + e_B`, `6 + 6 → 7`, exact). |

Everything runs signed (`IS_SIGNED = 1'b1` on every `shift_n`, `ext_n`, `align_cell_bfp`, `cpr_w_n`) and every `cpr_w_n` keeps `EXT = 0` — the mantissa widths and guard margins are byte-for-byte the baseline's.

## Interface

| Signal                       | Dir | Width   | Description                                                                                            |
| ---------------------------- | --- | ------- | ------------------------------------------------------------------------------------------------------ |
| `clk_i`                      | in  | 1       | Clock.                                                                                                 |
| `rst_ni`                     | in  | 1       | Asynchronous active-low reset.                                                                         |
| `a_dp8_i[0:15]`              | in  | 64 each | A operand per DP8 (8 × int8), from `disp_array_a`.                                                     |
| `b_dp8_i[0:15]`              | in  | 32 each | B operand per DP8 (8 × int4), from `disp_array_b`.                                                     |
| `is_signed_a_i[0:15]`        | in  | 1 each  | Per-DP8 A signedness, from `ctrl`.                                                                     |
| `is_signed_b_i[0:15]`        | in  | 1 each  | Per-DP8 B signedness, from `ctrl`.                                                                     |
| `exp_a_dp8_i[0:15]`          | in  | 6 each  | **NEW** — A format exponent per DP8, from `disp_array_exp_a_bfp`.                                      |
| `exp_b_dp8_i[0:15]`          | in  | 6 each  | **NEW** — B format exponent per DP8, from `disp_array_exp_b_bfp`.                                      |
| `sel_shift_i[2:0]`           | in  | 1 each  | Per-level shift enable: `[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`.                                |
| `en_level_i[2:0]`            | in  | 1 each  | Operand-isolation enable per tree branch (`[0]`=L0→L1, `[1]`=L1→L2, `[2]`=L2→L3); masks below the tap. |
| `l0_sum_o`/`l0_carry_o[0:7]` | out | 18 each | L0 taps (carry-save).                                                                                  |
| `l0_exp_o[0:7]`              | out | 7 each  | **NEW** — L0 tap scales.                                                                               |
| `l1_sum_o`/`l1_carry_o[0:3]` | out | 29 each | L1 taps.                                                                                               |
| `l1_exp_o[0:3]`              | out | 7 each  | **NEW** — L1 tap scales.                                                                               |
| `l2_sum_o`/`l2_carry_o[0:1]` | out | 37 each | L2 taps.                                                                                               |
| `l2_exp_o[0:1]`              | out | 7 each  | **NEW** — L2 tap scales.                                                                               |
| `l3_sum_o`/`l3_carry_o`      | out | 38      | L3 tap.                                                                                                |
| `l3_exp_o`                   | out | 7       | **NEW** — L3 tap scale.                                                                                |

Every tap is a carry-save pair (`sum + carry`) *plus a scale* — a tap reads as mantissa pair + exponent; the tree never resolves.

## Instantiation

```systemverilog
pe_array_bfp pe_array_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .b_dp8_i(b_dp8),
    .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
    .exp_a_dp8_i(exp_a_dp8), .exp_b_dp8_i(exp_b_dp8),
    .sel_shift_i(sel_shift), .en_level_i(en_level),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry), .l0_exp_o(l0_exp),
    .l1_sum_o(l1_sum), .l1_carry_o(l1_carry), .l1_exp_o(l1_exp),
    .l2_sum_o(l2_sum), .l2_carry_o(l2_carry), .l2_exp_o(l2_exp),
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry), .l3_exp_o(l3_exp)
);
```

## Internal logic

The mantissa datapath is [pe_array](./pe_array.md) verbatim — 16 `dp_8` leaves, the crossed L0 (`CX0 = 4·(n/2) + n%2`, `CX1 = CX0 + 2`), the balanced tree, the L0 register, the tap slices. What follows is the exponent sideband and the aligners threaded through it.

### The per-DP8 scale

The A exponents arrive from the row's [disp_array_exp_a_bfp](./disp_array_exp_a_bfp.md), the B exponents from the column's [disp_array_exp_b_bfp](./disp_array_exp_b_bfp.md); the two sidebands **meet only here**. One [add_n](./add_n.md) per DP8 forms the product scale `e_A + e_B` — 6 + 6 into 7 bits, exact, no bias in the datapath:

```systemverilog
add_n #(.WIDTH(EXP_IN_WIDTH), .CARRY(1)) add_n_exp_i (
    .in_0_i({1'b0, exp_a_dp8_i[i]}), .in_1_i({1'b0, exp_b_dp8_i[i]}), .cin_i(1'b0),
    .out_o(exp_dp8[i][EXP_IN_WIDTH-1:0]), .cout_o(exp_dp8[i][EXP_IN_WIDTH])
);
```

An idle DP8 must arrive with **both** sides already gated to zero (the dispatchers do this) so its scale is the minimum `0` and never wins a downstream max — otherwise its stray scale would right-shift the active data at a merge.

### The align cell at L0 / L2 / L3

At each aligning node the two width-matched carry-save operands (the `shift_n`'d hi pair and the `ext_n`'d lo pair) feed one `align_cell_bfp` with their two scales; it returns the four rows already aligned to `max` and forwards that `max` as the node scale. The compressor then runs exactly as in the baseline on the aligned rows:

```systemverilog
align_cell_bfp #(
    .WIDTH(DP8_WIDTH+SH0), .SIZE_0(2), .SIZE_1(2), .EXP_WIDTH(EXP_WIDTH), .IS_SIGNED(1'b1)
) align_cell_bfp_i (
    .in_0_i(hi_sh),  .exp_0_i(exp_dp8[CX0]),
    .in_1_i(lo_ext), .exp_1_i(exp_dp8[CX1]),
    .chain_en_i(1'b0), .chain_0_i(zero_ch), .chain_1_i(zero_ch),
    .chain_0_o(), .chain_1_o(),
    .out_o(cpr_in), .exp_o(l0_exp[n])
);
cpr_w_n #(.IN_WIDTH(DP8_WIDTH+SH0), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
    .in_i(cpr_in), .sum_o(l0_sum[n]), .carry_o(l0_carry[n])
);
```

`SIZE_0 = SIZE_1 = 2` because each operand is a `(sum, carry)` pair; both rows of the smaller-scale side shift together. The **fusion chain is unused inside the tree** (`chain_en_i = 1'b0`, chain outputs left open) — that machinery belongs to the accumulator; here each node aligns its own pair in isolation. L2 and L3 are the same cell scaled to their widths (`WIDTH = L1_WIDTH + SH2` at L2, `= L2_WIDTH` at L3), consuming the L1 / L2 node scales.

### Why L1 only forwards a max

L1's merge always recombines the **H and L halves of the same B block** — same element, same source exponent by the format-coherence rule — so its two inputs are already on one scale and there is nothing to shift. L1 therefore has **no aligner**; it just forwards the (equal) scale, computed as a max with a bare [sub_n_bfp](./sub_n_bfp.md) sign + a [mux_n](./mux_n.md), no shifter:

```systemverilog
sub_n_bfp #(.WIDTH(EXP_WIDTH)) sub_n_bfp_i (
    .in_0_i(l0_exp_q[2*j]), .in_1_i(l0_exp_q[2*j+1]), .abs_o(), .sign_o(exp_sign)
);
mux_n #(.WIDTH(EXP_WIDTH), .SIZE(2)) mux_n_exp_i (
    .in_i(exp_in), .sel_i(exp_sign), .out_o(l1_exp[j])
);
```

This keeps the scale tree monotone (`e_node = max` at every level) while spending nothing on the merge the format guarantees is already aligned — 11 aligners, not 15.

### Registered exponent and taps

The node scales track the mantissa exactly through the one pipeline stage: `l0_exp` is captured by a third `reg_n` bank alongside the two L0 sum/carry register banks, at full `EXP_WIDTH`:

```systemverilog
reg_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_L0)) reg_n_l0_exp_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(l0_exp), .q_o(l0_exp_q)
);
```

Every level then exports its scale next to the carry-save tap (`l0_exp_o = l0_exp_q`, `l1_exp_o = l1_exp`, `l2_exp_o = l2_exp`, `l3_exp_o` straight from the L3 cell), so the accumulator reads each tap as a mantissa pair plus a scale. As in the baseline, **L0 is the only registered stage** and L1/L2/L3 are combinational — one clock through the whole tree, exponent and mantissa in lockstep. `en_level_i` isolation, the crossover, per-level shifts, and the "which level a mode reads" mapping are all unchanged; see [pe_array](./pe_array.md).

## Verification

[tb_pe_array_bfp](../../tb/tb_pe_array_bfp.sv) wires the full BFP front end (`disp_array_a`/`disp_array_b` + `disp_array_exp_a_bfp`/`disp_array_exp_b_bfp`) into the tree and checks two ways: with **equal exponents** the taps are bit-identical to the baseline `pe_array` across all 11 modes (aligners transparent), and with **distinct exponents** each tap value and its exported scale match an align-then-reduce cascade golden — confirming the 11 aligner sites, the L1 max-forward, and the per-DP8 scale add.

Source: [pe_array_bfp.sv](../../rtl/pe_array_bfp.sv) — Testbench: [tb_pe_array_bfp.sv](../../tb/tb_pe_array_bfp.sv) — Diagram: [pe_array_bfp](../../doc/diagrams/pe_array_bfp.excalidraw)
