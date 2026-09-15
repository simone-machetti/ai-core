# PE Array (Square-BFP)

`pe_array_sqr_bfp` — the square-BFP PE array: [pe_array_bfp](./pe_array_bfp.md)'s exponent-aligned crossed reduction tree with a **per-DP8 square reconstruction front-end** in front of it. 16 [dp_8_sqr](./dp_8_sqr.md) cores produce the PE square-sums, and one [ext_inject_sqr_bfp](./ext_inject_sqr_bfp.md) folds each block's `−α` / `−β` / `C` into it — delivering the signed `2·P_j` at the block scale `E_j` **before** the crossed tree. From those leaves up, the tree is [pe_array_bfp](./pe_array_bfp.md) verbatim. Fixed to the PE.

## Purpose

The key framing: once each DP8 is combined to `2·P_j = PE_j − α_j − β_j + C_j` — a **signed** value at the single block scale `E_j = e_A,j + e_B,j` — the leaf is exactly `2×` the integer int8×int4 dot product. So the reduction is **not** [pe_array_sqr](./pe_array_sqr.md)'s tree; it is [pe_array_bfp](./pe_array_bfp.md)'s aligned/crossed tree, lifted with **+1-bit** taps to carry the doubled value. Only the **leaf front-end** (squares + combine + `C` + block-negate) is square-specific, and it is factored out into [ext_inject_sqr_bfp](./ext_inject_sqr_bfp.md).

Because `PE`, `−α`, `−β` and `C` all share the block scale `E_j`, the `PE − α − β + C` combine is a **per-DP8 [cpr_w_n](./cpr_w_n.md) 7:2** done *before* the radix shift and exponent alignment — and the crossed tree above it reverts to baseline-BFP's **2-row** DP8 pairs (one [align_cell_bfp](./align_cell_bfp.md) `SIZE = 2` + a **4:2** CPR per node). This is a pure **reassociation** of the older fused 14:2 L0 node (two 7-row bundles aligned and compressed together): the l0…l3 taps are bit-identical, but the alignment shrinks from 14 rows to 2. With all exponents equal the aligners are transparent and every tap resolves to `2·(A·B)`, bit-exact to the integer square identity (verified, 11/11 modes). The `½` is deferred to [acc_array_sqr_bfp](./acc_array_sqr_bfp.md).

## Parameters

None — fixed to the PE configuration; all `localparam`s. The key ones:

| Localparam                    | Value             | Meaning                                                              |
| ----------------------------- | ----------------- | -------------------------------------------------------------------- |
| `NUM_DP8`                     | 16                | [dp_8_sqr](./dp_8_sqr.md) cores driving the tree.                    |
| `NUM_ROW`                     | 7                 | 7:2 front-end inputs per DP8 (`{PE s/c, −α s/c, −β s/c, C}`).        |
| `NUM_L0`/`NUM_L1`/`NUM_L2`    | 8 / 4 / 2         | node count at L0/L1/L2 (L3 is a single node).                        |
| `NUM_NEG`                     | 6                 | block-negate gates (one per L0 node 0–5), remapped to the DP8 index. |
| `DP8_WIDTH`                   | 18                | each square-sum / `−α` / `−β` / `C` carry-save row width.            |
| `P_WIDTH`                     | 21                | `2·P` carry-save width (`DP8_WIDTH + ⌈log₂7⌉`); the 7:2 headroom.    |
| `SH0`/`SH1`/`SH2`             | 8 / 4 / 8         | per-level radix left-shift (L0/L1/L2; L3 has no shift).              |
| `L0_WIDTH`…`L3_WIDTH`         | 29 / 33 / 41 / 42 | internal node width at each level (= baseline-BFP + 3).              |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | 19 / 30 / 38 / 39 | tap width exported to the accumulator (= baseline-BFP + 1).          |
| `EXP_IN_WIDTH`                | 6                 | per-DP8 input exponent width (`e_A`, `e_B`).                         |
| `EXP_WIDTH`                   | 7                 | `E_j = e_A + e_B` scale (`EXP_IN_WIDTH + 1`), held exactly.          |

The per-DP8 7:2 and the crossed shift / ext / align all run **signed** (`IS_SIGNED = 1'b1`), because `2·P` carries the signed `−α`/`−β`/`C` and the (possibly negated) PE. This is unlike [pe_array_sqr](./pe_array_sqr.md), whose L0-hi path is PE-only and unsigned. Every crossed `cpr_w_n` runs `EXT = 0` except L3, which runs `EXT = L3_EXT = 1`.

## Interface

| Signal                                         | Dir | Width   | Description                                                                                            |
| ---------------------------------------------- | --- | ------- | ------------------------------------------------------------------------------------------------------ |
| `clk_i` / `rst_ni`                             | in  | 1       | Clock / async active-low reset.                                                                        |
| `a_dp8_i[0:15]`                                | in  | 64 each | A operand per DP8 (8 × pre-centered int8), from [disp_array_a_sqr](./disp_array_a_sqr.md).             |
| `b_dp8_i[0:15]`                                | in  | 32 each | B operand per DP8 (8 × pre-centered int4), from [disp_array_b_sqr](./disp_array_b_sqr.md).             |
| `alpha_sum_i`/`alpha_carry_i[0:15]`            | in  | 18 each | Per-DP8 `−α` carry-save, from [pe_array_alpha_sqr_bfp](./pe_array_alpha_sqr_bfp.md).                   |
| `beta_sum_i`/`beta_carry_i[0:15]`              | in  | 18 each | Per-DP8 `−β` carry-save, from [pe_array_beta_sqr_bfp](./pe_array_beta_sqr_bfp.md).                     |
| `const_dp8_i[0:15]`                            | in  | 18 each | Per-DP8 signed constant `C_j`, from [const_sqr_bfp](./const_sqr_bfp.md).                               |
| `neg_i[5:0]`                                   | in  | 6       | Per-block negate (modes 10/11): `neg_i[n]` complements L0 node `n`'s lo DP8 (`CX1`).                   |
| `zero_i[0:15]`                                 | in  | 1 each  | Per-DP8 idle-zero: gates that DP8's `−α`/`−β`/`C` to a real 0 (handled in the front-end).              |
| `exp_a_dp8_i[0:15]`                            | in  | 6 each  | Per-DP8 `e_A`, from [disp_array_exp_a_sqr_bfp](./disp_array_exp_a_sqr_bfp.md).                         |
| `exp_b_dp8_i[0:15]`                            | in  | 6 each  | Per-DP8 `e_B`, from [disp_array_exp_b_sqr_bfp](./disp_array_exp_b_sqr_bfp.md).                         |
| `sel_shift_i[2:0]`                             | in  | 1 each  | Per-level radix-shift enable (`[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`).                         |
| `en_level_i[2:0]`                              | in  | 1 each  | Operand-isolation enable per tree branch (`[0]`=L0→L1, `[1]`=L1→L2, `[2]`=L2→L3); masks below the tap. |
| `l0_sum_o`/`l0_carry_o[0:7]`                   | out | 19 each | L0 data taps (carry-save, `2·P`).                                                                      |
| `l0_exp_o[0:7]`                                | out | 7 each  | L0 exponent taps (subtree scale).                                                                      |
| `l1_sum_o`/`l1_carry_o[0:3]` / `l1_exp_o[0:3]` | out | 30 / 7  | L1 data + exponent taps.                                                                               |
| `l2_sum_o`/`l2_carry_o[0:1]` / `l2_exp_o[0:1]` | out | 38 / 7  | L2 data + exponent taps.                                                                               |
| `l3_sum_o`/`l3_carry_o` / `l3_exp_o`           | out | 39 / 7  | L3 data + exponent tap.                                                                                |

Every data tap is a carry-save pair (`sum + carry`); the tree never resolves. Each level also exports a 7-bit **exponent tap** — the running max scale of its subtree — that [pe_array_bfp](./pe_array_bfp.md) added and this variant carries unchanged.

## Instantiation

```systemverilog
pe_array_sqr_bfp pe_array_sqr_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .b_dp8_i(b_dp8),
    .alpha_sum_i(alpha_sum), .alpha_carry_i(alpha_carry),
    .beta_sum_i(beta_sum), .beta_carry_i(beta_carry),
    .const_dp8_i(const_dp8), .neg_i(neg), .zero_i(zero_dp8),
    .exp_a_dp8_i(exp_a_dp8), .exp_b_dp8_i(exp_b_dp8),
    .sel_shift_i(sel_shift), .en_level_i(en_level),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry), .l0_exp_o(l0_exp),
    .l1_sum_o(l1_sum), .l1_carry_o(l1_carry), .l1_exp_o(l1_exp),
    .l2_sum_o(l2_sum), .l2_carry_o(l2_carry), .l2_exp_o(l2_exp),
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry), .l3_exp_o(l3_exp)
);
```

## Internal logic

The datapath is: **16 [dp_8_sqr](./dp_8_sqr.md) cores + 16 `add_n` exponents → one [ext_inject_sqr_bfp](./ext_inject_sqr_bfp.md) (per-DP8 idle-gate → block-negate → 7:2 → `2·P`) → [pe_array_bfp](./pe_array_bfp.md)'s crossed L0/L1/L2/L3 tree + exponent max-tree → carry-save + exponent taps at each level.** The whole tree is [pe_array_bfp](./pe_array_bfp.md) verbatim on 2-row DP8 pairs; this page covers the front-end, the neg remap, and the width/signedness deltas.

### The reconstruction front-end

The 16 [dp_8_sqr](./dp_8_sqr.md) square-sums (`dp8_sum`/`dp8_carry`) and the raw `−α`/`−β`/`C` buses feed a single [ext_inject_sqr_bfp](./ext_inject_sqr_bfp.md), which per DP8 idle-gates the external terms, block-negates the mantissa bundle, and 7:2-compresses `{PE, −α, −β, C}` into the signed `2·P_j` pair at `P_WIDTH = 21` bits:

```systemverilog
ext_inject_sqr_bfp #(.NUM_DP8(NUM_DP8), .DP8_WIDTH(DP8_WIDTH)) ext_inject_sqr_bfp_i (
    .pe_sum_i(dp8_sum), .pe_carry_i(dp8_carry),
    .alpha_sum_i(alpha_sum_i), /* … β, const, zero … */
    .neg_i(dp8_neg), .sum_o(p_sum), .carry_o(p_carry)
);
```

This is the block that keeps the α/β generators **neg-agnostic** and [const_sqr_bfp](./const_sqr_bfp.md) **idle-gate-free** — both are handled inside the front-end.

### The block-negate remap

The `neg_i` port is **6-bit**, indexed by L0 node (one bit per negatable node 0–5) exactly as [pe_array_sqr](./pe_array_sqr.md). But the front-end negates per **DP8**, so an `always_comb` scatters the six node bits onto the DP8s they select — always the lo (`CX1`) operand of nodes 0–5, i.e. DP8 {2, 3, 6, 7, 10, 11}, the union of modes 10/11:

```systemverilog
always_comb begin
    dp8_neg = '0;
    for (int nn = 0; nn < NUM_NEG; nn++)
        dp8_neg[4*(nn/2) + (nn%2) + 2] = neg_i[nn];
end
```

### The crossed tree (baseline-BFP)

Each L0 node crosses two DP8s — `CX0 = 4·(n/2)+n%2` (hi) and `CX1 = CX0+2` (lo) — feeding their `2·P` pairs (not raw square-sums) through baseline-BFP's 2-row path: `shift_n` `<<8` on hi, `ext_n` on lo, one [align_cell_bfp](./align_cell_bfp.md) `SIZE_0 = SIZE_1 = 2` to `max(E_CX0, E_CX1)`, then a **4:2** [cpr_w_n](./cpr_w_n.md):

```systemverilog
shift_n #(.WIDTH(P_WIDTH), .SIZE(2), .SHIFT(SH0), .IS_SIGNED(1'b1)) shift_n_i ( … );
ext_n   #(.WIDTH(P_WIDTH), .SIZE(2), .EXT(SH0), .IS_SIGNED(1'b1)) ext_n_i ( … );
align_cell_bfp #(.WIDTH(L0_WIDTH), .SIZE_0(2), .SIZE_1(2), .EXP_WIDTH(EXP_WIDTH), .IS_SIGNED(1'b1))
    align_cell_bfp_i ( … .exp_o(l0_exp[n]) );
cpr_w_n #(.IN_WIDTH(L0_WIDTH), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
    .in_i(cpr_in), .sum_o(l0_sum[n]), .carry_o(l0_carry[n])
);
```

L1 does **no** data align (radix `<<4` + `sub_n_bfp` sign + `mux_n` to forward the max exponent); L2 and L3 align again with [align_cell_bfp](./align_cell_bfp.md). All of L1/L2/L3, the exponent max-tree, and the per-level exponent taps are [pe_array_bfp](./pe_array_bfp.md) verbatim.

### Exponents and the max-tree

Each DP8's scale is formed by a 6+6→7 `add_n`, `E_j = e_A,j + e_B,j`, so `EXP_WIDTH = 7` holds the product-domain scale exactly:

```systemverilog
add_n #(.WIDTH(EXP_IN_WIDTH), .CARRY(1)) add_n_exp_i (
    .in_0_i({1'b0, exp_a_dp8_i[i]}), .in_1_i({1'b0, exp_b_dp8_i[i]}), .cin_i(1'b0),
    .out_o(exp_dp8[i][EXP_IN_WIDTH-1:0]), .cout_o(exp_dp8[i][EXP_IN_WIDTH])
);
```

L0 aligns each crossed pair and forwards `max(E_CX0, E_CX1)`; L1 forwards the max via `sub_n_bfp` + `mux_n`; L2/L3 align. This — and the per-level exponent taps — is [pe_array_bfp](./pe_array_bfp.md) verbatim.

### Widths and taps

The square-sum leaves are 18-bit; the per-DP8 `2·P` is `P_WIDTH = 21` (the `⌈log₂7⌉ = 3` headroom that keeps the 7:2 output sign-consistent for the crossed-tree sign-extension). The node widths follow at **29 / 33 / 41 / 42** (baseline-BFP + 3). The taps still carry `2·P`, one bit wider than baseline BFP:

```systemverilog
localparam int L0_TAP_WIDTH = 19;   // = baseline-BFP (18) + 1  (carries 2·P)
localparam int L1_TAP_WIDTH = 30;
localparam int L2_TAP_WIDTH = 38;
localparam int L3_TAP_WIDTH = 39;
```

Taps are sliced from the low bits of each node exactly as the baseline. **L0 is the only registered stage** — two `reg_n` banks (data at the full 29-bit node width, not the 19-bit tap) plus one `reg_n` for the L0 exponent, so the R16 modes' `<<8` intermediate reaches L1 without truncation. L1/L2/L3 and the exponent max-tree are combinational — one clock through the whole tree. Reading a mode's result at the right level/tap follows [pe_array_bfp](./pe_array_bfp.md) (8→L0, 4→L1, 2→L2, 1→L3; a complex output reads one level shallower).

These widths are verified sign-consistent across all 11 modes under corner-biased operands by [tb_pe_array_sqr_bfp](../testbenches/tb_pe_array_sqr_bfp.md) — Pass A (equal exponents) bit-exact to `2·A·B`, Pass B (distinct legal BFP exponents) exponent-exact plus a per-tap truncation window — including the whole-bundle block-negate (10/11) and the `zero_i` idle clean-zero. The one-`2¹⁸`-off bug that appears if the front-end 7:2 drops its `EXT` guard bits is caught here.

Source: [pe_array_sqr_bfp.sv](../../rtl/pe_array_sqr_bfp.sv) — Testbench: [tb_pe_array_sqr_bfp.sv](../../tb/tb_pe_array_sqr_bfp.sv) — Diagram: [pe_array_sqr_bfp](../../doc/diagrams/pe_array_sqr_bfp.excalidraw)
