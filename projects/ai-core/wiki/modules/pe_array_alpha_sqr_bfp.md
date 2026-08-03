# PE Array Alpha (Square-BFP)

`pe_array_alpha_sqr_bfp` — the per-row **A-only correction generator** for the square-BFP PE, made **tree-less**. It is [pe_array_alpha_sqr](./pe_array_alpha_sqr.md) stripped down to just its 16 [dp_8_alpha_sqr](./dp_8_alpha_sqr.md) leaves: the 4-level crossed tree, the L0 register, the operand isolation and — crucially — the complex-mode block negate are all gone. It emits the 16 per-DP8 **`−α`** carry-save pairs, which feed [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s L0 combine directly.

## Purpose

In the square-BFP PE the reduction is done **once**, inside [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s exponent-aligned tree, on the *combined* per-DP8 leaf `2·P_j = PE_j − α_j − β_j + C_j`. The α term must therefore arrive **at the leaf, un-reduced** — one `−α_j` carry-save pair per DP8, folded in at that PE's L0 node under the block's own scale. So there is no tree here to mirror [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) with: the generator collapses to the 16 [dp_8_alpha_sqr](./dp_8_alpha_sqr.md) cores and nothing else. One instance per grid **row**, fanned into every PE in that row.

This is the central delta from [pe_array_alpha_sqr](./pe_array_alpha_sqr.md), which reduces its 16 `ALPHA_DP8` through the *same* linear tree as the PE. Because [pe_array_sqr_bfp](./pe_array_sqr_bfp.md) reduces the combined leaf instead, α/β and PE still pass through one identical reduction — just downstream, not here.

## Output — always emits `−α`, neg-agnostic

Each core's raw square-sum `ALPHA_DP8` is **one's-complemented at the output** so the module emits **`−α`**: each carry-save pair resolves to `−ALPHA_DP8 − 2`. This lets [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s L0 CPR just **add** the α term (`PE − α − β + C` becomes a pure carry-save sum, no subtractor). The deferred `−2` per DP8 (one for α, one for β) is folded into [const_sqr_bfp](./const_sqr_bfp.md)'s per-DP8 constant (the `+4`).

```systemverilog
assign alpha_sum_o[i]   = ~dp8_sum[i];
assign alpha_carry_o[i] = ~dp8_carry[i];
```

Unlike [pe_array_alpha_sqr](./pe_array_alpha_sqr.md), the generator is **NEG-AGNOSTIC**: it carries **no `neg_i` and no `comp_n`**, always emitting `−α`. The complex-mode block negate for modes 10/11 lives entirely in [pe_array_sqr_bfp](./pe_array_sqr_bfp.md), which one's-complements the whole `{PE, −α, −β}` lo mantissa bundle (flipping `−α` back to `+α`). This keeps the generator combinational and identical across all modes.

**No `zero_i` port** (unlike the β generator): `ctrl_sqr` forces `is_signed_b = 1` for idle DP8s, so a [disp_array_a_sqr](./disp_array_a_sqr.md)-zeroed A sign-extends to a real zero inside [dp_8_alpha_sqr](./dp_8_alpha_sqr.md); the α low block has no fixed `−8` to leak. ([pe_array_beta_sqr_bfp](./pe_array_beta_sqr_bfp.md) does keep `zero_i` for exactly that reason.) The remaining idle clean-up (the redundant carry-save an idle leaf still emits) is handled by [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s `zero_i` gate.

## Parameters

None — fixed to the PE configuration; all `localparam`s. `NUM_DP8 = 16`, `A_DP8_WIDTH = 64`, `LANES = 8`, `IN_WIDTH_A = 8` (int8 lanes per DP8), `DP8_WIDTH = 18` (per-DP8 square-sum, unsigned before the output complement).

## Interface

Compared with [pe_array_alpha_sqr](./pe_array_alpha_sqr.md): the tree ports (`clk_i`/`rst_ni`, `neg_i`, `sel_shift_i`, `en_level_i`, the L1–L3 taps) are **gone**, and the outputs become the 16 per-DP8 leaves.

| Signal                | Dir | Width   | Description                                                                            |
| --------------------- | --- | ------- | -------------------------------------------------------------------------------------- |
| `a_dp8_i[0:15]`       | in  | 64 each | Pre-centered A per DP8 (8 × int8), from [disp_array_a_sqr](./disp_array_a_sqr.md).     |
| `is_signed_b_i[0:15]` | in  | 1 each  | Removed-B signedness (drives the α bias inside [dp_8_alpha_sqr](./dp_8_alpha_sqr.md)). |
| `alpha_sum_o[0:15]`   | out | 18 each | Per-DP8 `−α` sum row (one's-complemented `dp8_sum`).                                   |
| `alpha_carry_o[0:15]` | out | 18 each | Per-DP8 `−α` carry row (one's-complemented `dp8_carry`).                               |

Combinational — no clock. The pipeline register lives in [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s L0, which captures the whole combined bundle.

## Instantiation

```systemverilog
pe_array_alpha_sqr_bfp pe_array_alpha_sqr_bfp_i (
    .a_dp8_i(a_dp8), .is_signed_b_i(is_signed_b),
    .alpha_sum_o(alpha_sum), .alpha_carry_o(alpha_carry)
);
```

## Internal logic

For each of the 16 DP8s, slice the 64-bit `a_dp8_i` into its 8 int8 lanes, feed one [dp_8_alpha_sqr](./dp_8_alpha_sqr.md), and one's-complement its carry-save pair to the output:

```systemverilog
dp_8_alpha_sqr dp_8_alpha_sqr_i (
    .a_i(a_lane), .is_signed_b_i(is_signed_b_i[i]),
    .sum_o(dp8_sum[i]), .carry_o(dp8_carry[i])
);
assign alpha_sum_o[i]   = ~dp8_sum[i];
assign alpha_carry_o[i] = ~dp8_carry[i];
```

Diagram: [pe_array_alpha_sqr_bfp](../../doc/diagrams/pe_array_alpha_sqr_bfp.excalidraw).

Source: [pe_array_alpha_sqr_bfp.sv](../../rtl/pe_array_alpha_sqr_bfp.sv) — Testbench: [tb_pe_array_alpha_sqr_bfp.sv](../../tb/tb_pe_array_alpha_sqr_bfp.sv) — Diagram: [pe_array_alpha_sqr_bfp](../../doc/diagrams/pe_array_alpha_sqr_bfp.excalidraw)
