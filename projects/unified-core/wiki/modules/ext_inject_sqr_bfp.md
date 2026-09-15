# External-term Injection (Square-BFP)

`ext_inject_sqr_bfp` — the per-DP8 **square reconstruction front-end** of [pe_array_sqr_bfp](./pe_array_sqr_bfp.md). For each of the 16 DP8 blocks it folds the square-sum `PE` (the [dp_8_sqr](./dp_8_sqr.md) carry-save pair), the per-row `−α` and per-column `−β` carry-save pairs, and the per-DP8 constant `C` into a single carry-save pair **`2·P_j` at the block's own scale** — with no alignment, because `PE`, `−α`, `−β` and `C` all live in the one block scale `E_j = e_A,j + e_B,j`. One instantiation processes all `NUM_DP8` blocks.

## Purpose

The square identity is `2·P_j = PE_j − α_j − β_j + C_j`. Because those four terms share `E_j`, the combine can be done **per DP8, before** the crossed tree's radix shift and exponent alignment — a pure reassociation of the previous fused L0 node. This front-end is exactly that reassociation: 16 independent 7-input reductions, one per block, each producing the leaf the tree then crosses and reduces. It replaces the old two-crossed-bundle **14:2** L0 node with a per-DP8 **7:2** here plus a baseline-BFP **4:2** cross in [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) — bit-identical taps, much narrower alignment (2-row instead of 14-row). It is the block that turns the square-BFP PE array back into baseline-BFP from the crossed tree up.

## Parameters

| Parameter / localparam | Value                              | Meaning                                                                                                                    |
| ---------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `NUM_DP8`              | 16                                 | DP8 blocks processed (one reduction each).                                                                                 |
| `DP8_WIDTH`            | 18                                 | Per-block input word width (`PE` / `−α` / `−β` / `C`).                                                                     |
| `NUM_MANT`             | 6                                  | Negated rows `{PE s/c, −α s/c, −β s/c}` fed to `comp_n`.                                                                   |
| `NUM_GATE`             | 5                                  | Idle-gated rows `{−α s/c, −β s/c, C}`.                                                                                     |
| `NUM_ROW`              | 7                                  | 7:2 inputs `{NUM_MANT mantissa rows, C}`.                                                                                  |
| `OUT_WIDTH`            | `DP8_WIDTH + $clog2(NUM_ROW)` = 21 | `2·P` carry-save width; the `⌈log₂7⌉ = 3` headroom keeps the 7:2 output sign-consistent for the downstream sign-extension. |

`NUM_DP8` / `DP8_WIDTH` are `parameter`; the rest are `localparam` fixed by the reconstruction.

## Interface

| Signal                                | Dir | Width   | Description                                                                              |
| ------------------------------------- | --- | ------- | ---------------------------------------------------------------------------------------- |
| `pe_sum_i` / `pe_carry_i[0:15]`       | in  | 18 each | Per-DP8 square-sum `PE`, from [dp_8_sqr](./dp_8_sqr.md).                                 |
| `alpha_sum_i` / `alpha_carry_i[0:15]` | in  | 18 each | Per-DP8 `−α`, from [pe_array_alpha_sqr_bfp](./pe_array_alpha_sqr_bfp.md).                |
| `beta_sum_i` / `beta_carry_i[0:15]`   | in  | 18 each | Per-DP8 `−β`, from [pe_array_beta_sqr_bfp](./pe_array_beta_sqr_bfp.md).                  |
| `const_i[0:15]`                       | in  | 18 each | Per-DP8 signed constant `C_j`, from [const_sqr_bfp](./const_sqr_bfp.md).                 |
| `zero_i[0:15]`                        | in  | 1 each  | Per-DP8 idle-zero: gates that block's `−α`/`−β`/`C` to a real 0.                         |
| `neg_i[15:0]`                         | in  | 16      | Per-DP8 block negate (packed): `neg_i[j]` one's-complements block `j`'s mantissa bundle. |
| `sum_o` / `carry_o[0:15]`             | out | 21 each | Per-DP8 `2·P_j` carry-save pair.                                                         |

`neg_i` is **per-DP8** here; [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) maps its node-indexed 6-bit block-negate onto the DP8 index before driving this port.

## Instantiation

```systemverilog
ext_inject_sqr_bfp #(.NUM_DP8(NUM_DP8), .DP8_WIDTH(DP8_WIDTH)) ext_inject_sqr_bfp_i (
    .pe_sum_i(dp8_sum),       .pe_carry_i(dp8_carry),
    .alpha_sum_i(alpha_sum_i), .alpha_carry_i(alpha_carry_i),
    .beta_sum_i(beta_sum_i),   .beta_carry_i(beta_carry_i),
    .const_i(const_dp8_i),     .zero_i(zero_i), .neg_i(dp8_neg),
    .sum_o(p_sum),             .carry_o(p_carry)
);
```

## Internal logic

Combinational; one `generate` block per DP8. Three stages: **idle-gate → block-negate → 7:2 compress**.

### Idle-gate the external terms

An idle DP8's `−α`/`−β` are one's-complements of zero (`~0 = −1`, not 0) and its `C` is a nonzero LUT value, so all five rows must be forced to a real 0 when the block is idle. One [gate_n](./gate_n.md) `#(SIZE = 5)` gates `{−α s/c, −β s/c, C}` on `zero_i[j]`. The `PE` pair is **not** gated — the multiply path self-zeroes (`0² = 0`), so an idle PE is already a clean carry-save zero:

```systemverilog
gate_n #(.WIDTH(DP8_WIDTH), .SIZE(NUM_GATE)) gate_n_idle_i (
    .in_i(gate_in), .sel_i(zero_i[i]), .out_o(gate_out)
);
```

This is why [const_sqr_bfp](./const_sqr_bfp.md) needs no idle-gate of its own — this front-end masks it.

### Block-negate the mantissa bundle

Modes 10/11 negate a subset of blocks. Because the α/β generators are **neg-agnostic** (they always emit `−α`/`−β`), the sign flip is applied here by one [comp_n](./comp_n.md) `#(SIZE = 6)` over the six-row mantissa bundle `{PE s/c, −α s/c, −β s/c}` (the idle-gated `−α`/`−β`) on `neg_i[j]`. The constant row **bypasses** the negate — [const_sqr_bfp](./const_sqr_bfp.md) already emits the pre-negated per-DP8 constant (`2 − C_cent`) un-negated, so it lands correct after the flip:

```systemverilog
comp_n #(.WIDTH(DP8_WIDTH), .SIZE(NUM_MANT)) comp_n_i (
    .in_i(mant_raw), .neg_i(neg_i[i]), .out_o(mant)
);
```

Complementing `{PE, −α, −β}` flips the block to `{−PE, +α, +β}`, so the combine contributes `−(PE − α − β) = −2·P`. Because `neg_i` never coincides with `zero_i` (negate is active only in modes 10/11, which have no idle DP8s), `comp_n` never sees a self-zeroed idle PE.

### The 7:2 combine

The six mantissa rows plus the (un-negated) constant row feed one [cpr_w_n](./cpr_w_n.md) `#(IN_SIZE = 7, IS_SIGNED)`, collapsing `{PE, −α, −β, C}` to the carry-save pair `2·P_j`:

```systemverilog
cpr_w_n #(.IN_WIDTH(DP8_WIDTH), .IN_SIZE(NUM_ROW), .IS_SIGNED(1'b1)) cpr_w_n_i (
    .in_i(row), .sum_o(sum_o[i]), .carry_o(carry_o[i])
);
```

The compressor uses its **default** `EXT = ⌈log₂7⌉ = 3`, widening the output to `OUT_WIDTH = 21`. That headroom is required: a signed multi-row carry-save reduction is only sign-consistent when the guard bits are kept, and `pe_array_sqr_bfp`'s crossed tree sign-extends this pair. An `EXT = 0` here breaks sign-consistency and the taps miss by exactly one `2¹⁸` in the R16 modes — the bug this width fixes.

## Verification

Exercised in place by [tb_pe_array_sqr_bfp](../testbenches/tb_pe_array_sqr_bfp.md) (the tb drives the `−α`/`−β`/`C` ports and checks every crossed-tree tap resolves to `2·A·B`) and end to end by [tb_acc_array_sqr_bfp](../testbenches/tb_acc_array_sqr_bfp.md) and [tb_top_NxN_sqr_bfp](../testbenches/tb_top_NxN_sqr_bfp.md). All 11 modes, corner-biased, 0 mismatches.

Source: [ext_inject_sqr_bfp.sv](../../rtl/ext_inject_sqr_bfp.sv) — Diagram: [ext_inject_sqr_bfp](../../doc/diagrams/ext_inject_sqr_bfp.excalidraw)
