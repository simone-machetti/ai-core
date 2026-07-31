# PE Array Beta (Square-BFP)

`pe_array_beta_sqr_bfp` — the per-column **B-only correction generator** for the square-BFP PE, made **tree-less**. It is [pe_array_beta_sqr](./pe_array_beta_sqr.md) stripped down to just its 16 [dp_8_beta_sqr](./dp_8_beta_sqr.md) leaves: the 4-level crossed tree, the L0 register, the operand isolation and the complex-mode block negate are all gone. It emits the 16 per-DP8 **`−β`** carry-save pairs, which feed [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s L0 combine directly.

## Purpose

In the square-BFP PE the reduction happens **once**, inside [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s exponent-aligned tree, on the *combined* per-DP8 leaf `2·P_j = PE_j − α_j − β_j + C_j`. The β term must therefore arrive **at the leaf, un-reduced** — one `−β_j` carry-save pair per DP8, folded in at that PE's L0 node under the block's own scale. So there is no tree to mirror here: the generator collapses to the 16 [dp_8_beta_sqr](./dp_8_beta_sqr.md) cores. One instance per grid **column**, fanned into every PE in that column. See [BFP_imp.md](../../doc/BFP_imp.md) §9.

This is the central delta from [pe_array_beta_sqr](./pe_array_beta_sqr.md), which reduces its 16 `BETA_DP8` through the *same* linear tree as the PE; the square-BFP PE reduces the combined leaf instead.

## Output — always emits `−β`, neg-agnostic

Each core's raw square-sum `BETA_DP8` is **one's-complemented at the output** so the module emits **`−β`**: each carry-save pair resolves to `−BETA_DP8 − 2`. This lets [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s L0 CPR just **add** the β term (`PE − α − β + C` becomes a pure carry-save sum, no subtractor). The deferred `−2` per DP8 (one for α, one for β) is folded into [const_sqr_bfp](./const_sqr_bfp.md)'s per-DP8 constant (the `+4`).

```systemverilog
assign beta_sum_o[i]   = ~dp8_sum[i];
assign beta_carry_o[i] = ~dp8_carry[i];
```

Like [pe_array_alpha_sqr_bfp](./pe_array_alpha_sqr_bfp.md), the generator is **NEG-AGNOSTIC**: no `neg_i`, no `comp_n`, always `−β`. The complex-mode block negate for modes 10/11 lives entirely in [pe_array_sqr_bfp](./pe_array_sqr_bfp.md), which one's-complements the whole `{PE, −α, −β}` lo mantissa bundle (flipping `−β` back to `+β`).

## `zero_i` is kept (unlike alpha)

The β generator **does** carry a per-DP8 `zero_i`. The β **low** block has a fixed `−8` centering offset, so a [disp_array_b_sqr](./disp_array_b_sqr.md)-zeroed idle DP8 would still inject `(−8)² = 64` per lane; [dp_8_beta_sqr](./dp_8_beta_sqr.md) forces that block to a real zero on `zero_i`. ([pe_array_alpha_sqr_bfp](./pe_array_alpha_sqr_bfp.md) needs no such port — its idle A sign-extends to zero because `ctrl_sqr` forces `is_signed_b = 1`.) This is the same `zero_i` the dispatchers and [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) use.

## Parameters

None — fixed to the PE configuration; all `localparam`s. `NUM_DP8 = 16`, `B_DP8_WIDTH = 32`, `LANES = 8`, `IN_WIDTH_B = 4` (int4 lanes per DP8), `DP8_WIDTH = 18`.

## Interface

Compared with [pe_array_beta_sqr](./pe_array_beta_sqr.md): the tree ports (`clk_i`/`rst_ni`, `neg_i`, `sel_shift_i`, `en_level_i`, the L1–L3 taps) are **gone**, and the outputs become the 16 per-DP8 leaves.

| Signal                  | Dir | Width   | Description                                                             |
| ----------------------- | --- | ------- | ----------------------------------------------------------------------- |
| `b_dp8_i[0:15]`         | in  | 32 each | Pre-centered B per DP8 (8 × int4), from [disp_array_b_sqr](./disp_array_b_sqr.md). |
| `is_signed_a_i[0:15]`   | in  | 1 each  | Removed A-high signedness (drives the β high-block bias inside [dp_8_beta_sqr](./dp_8_beta_sqr.md)). |
| `zero_i[0:15]`          | in  | 1 each  | Idle-zero for the β low block (its fixed `−8` would otherwise leak `64`). |
| `beta_sum_o[0:15]`      | out | 18 each | Per-DP8 `−β` sum row (one's-complemented `dp8_sum`).                    |
| `beta_carry_o[0:15]`    | out | 18 each | Per-DP8 `−β` carry row (one's-complemented `dp8_carry`).               |

Combinational — no clock. The pipeline register lives in [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s L0.

## Instantiation

```systemverilog
pe_array_beta_sqr_bfp pe_array_beta_sqr_bfp_i (
    .b_dp8_i(b_dp8), .is_signed_a_i(is_signed_a), .zero_i(zero_dp8),
    .beta_sum_o(beta_sum), .beta_carry_o(beta_carry)
);
```

## Internal logic

For each of the 16 DP8s, slice the 32-bit `b_dp8_i` into its 8 int4 lanes, feed one [dp_8_beta_sqr](./dp_8_beta_sqr.md), and one's-complement its carry-save pair to the output:

```systemverilog
dp_8_beta_sqr dp_8_beta_sqr_i (
    .b_i(b_lane), .is_signed_a_i(is_signed_a_i[i]), .zero_i(zero_i[i]),
    .sum_o(dp8_sum[i]), .carry_o(dp8_carry[i])
);
assign beta_sum_o[i]   = ~dp8_sum[i];
assign beta_carry_o[i] = ~dp8_carry[i];
```

Diagram: [pe_array_beta_sqr_bfp](../../doc/diagrams/pe_array_beta_sqr_bfp.excalidraw).

Source: [pe_array_beta_sqr_bfp.sv](../../rtl/pe_array_beta_sqr_bfp.sv) — Testbench: [tb_pe_array_beta_sqr_bfp.sv](../../tb/tb_pe_array_beta_sqr_bfp.sv) — Diagram: [pe_array_beta_sqr_bfp](../../doc/diagrams/pe_array_beta_sqr_bfp.excalidraw)
