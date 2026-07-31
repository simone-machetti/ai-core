# PE Array (Square-BFP)

`pe_array_sqr_bfp` — the square-BFP PE array: [pe_array_bfp](./pe_array_bfp.md)'s exponent-aligned crossed reduction tree with a **square front-end** bolted onto its L0. 16 [dp_8_sqr](./dp_8_sqr.md) cores produce the PE square-sums, and the per-row `−α` / per-column `−β` carry-save pairs plus the per-DP8 constant are folded in **at L0** — so each leaf becomes the signed `2·P_j` at the block scale, and the tree above L0 is [pe_array_bfp](./pe_array_bfp.md) verbatim. Fixed to the PE.

## Purpose

The key framing (see [BFP_imp.md](../../doc/BFP_imp.md) §9): once each DP8 is combined to `2·P_j = PE_j − α_j − β_j + C_j` — a **signed** value at the single block scale `E_j = e_A,j + e_B,j` — the leaf is exactly `2×` the integer int8×int4 dot product. So the reduction is **not** [pe_array_sqr](./pe_array_sqr.md)'s tree; it is [pe_array_bfp](./pe_array_bfp.md)'s aligned/crossed tree, lifted with **+1-bit** taps to carry the doubled value. Only the **leaf front-end** (squares + combine + `C` + block-negate) is square-specific.

The clever part is that the combine and the reduction's first crossed merge happen in **one shot**. Each L0 node takes its two crossed DP8s as two 7-row bundles `{PE s/c, −α s/c, −β s/c, C}`, aligns them to a common scale with one [align_cell_bfp](./align_cell_bfp.md), and a single **14:2 CPR** does the `PE − α − β + C` combine **and** the cross-merge together — delivering `D = 2·P` at the node scale. With all exponents equal the aligners are transparent and every tap resolves to `2·(A·B)`, bit-exact to the integer square identity (verified, 11/11 modes). The `½` is deferred to [acc_array_sqr_bfp](./acc_array_sqr_bfp.md).

## Parameters

None — fixed to the PE configuration; all `localparam`s. The key ones:

| Localparam                    | Value             | Meaning                                                              |
| ----------------------------- | ----------------- | -------------------------------------------------------------------- |
| `NUM_DP8`                     | 16                | [dp_8_sqr](./dp_8_sqr.md) cores driving the tree.                    |
| `NUM_ROW`                     | 7                 | rows per aligned L0 bundle (`{PE s/c, −α s/c, −β s/c, C}`).          |
| `NUM_CPR`                     | 14                | L0 combine width — the two crossed 7-row bundles.                    |
| `NUM_L0`/`NUM_L1`/`NUM_L2`    | 8 / 4 / 2         | node count at L0/L1/L2 (L3 is a single node).                        |
| `NUM_NEG`                     | 6                 | `comp_n` block-negate gates (one per L0 node 0–5).                   |
| `DP8_WIDTH`                   | 18                | each square-sum / `−α` / `−β` / `C` carry-save row width.            |
| `SH0`/`SH1`/`SH2`             | 8 / 4 / 8         | per-level radix left-shift (L0/L1/L2; L3 has no shift).              |
| `L0_WIDTH`…`L3_WIDTH`         | 26 / 30 / 38 / 39 | internal node width at each level.                                   |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | 19 / 30 / 38 / 39 | tap width exported to the accumulator (= baseline-BFP + 1).          |
| `EXP_IN_WIDTH`                | 6                 | per-DP8 input exponent width (`e_A`, `e_B`).                         |
| `EXP_WIDTH`                   | 7                 | `E_j = e_A + e_B` scale (`EXP_IN_WIDTH + 1`), held exactly.          |

Everything runs **signed** (`IS_SIGNED = 1'b1`) throughout — including the L0 hi `shift_n` and lo `ext_n` — because the bundle carries signed `−α`/`−β`/`C` and the (possibly negated) PE. This is unlike [pe_array_sqr](./pe_array_sqr.md), whose L0-hi path is PE-only and unsigned. Every `cpr_w_n` runs `EXT = 0` except L3, which runs `EXT = L3_EXT = 1`.

## Interface

| Signal                       | Dir | Width   | Description                                                                                            |
| ---------------------------- | --- | ------- | ------------------------------------------------------------------------------------------------------ |
| `clk_i` / `rst_ni`           | in  | 1       | Clock / async active-low reset.                                                                       |
| `a_dp8_i[0:15]`              | in  | 64 each | A operand per DP8 (8 × pre-centered int8), from [disp_array_a_sqr](./disp_array_a_sqr.md).            |
| `b_dp8_i[0:15]`              | in  | 32 each | B operand per DP8 (8 × pre-centered int4), from [disp_array_b_sqr](./disp_array_b_sqr.md).            |
| `alpha_sum_i`/`alpha_carry_i[0:15]` | in | 18 each | Per-DP8 `−α` carry-save, from [pe_array_alpha_sqr_bfp](./pe_array_alpha_sqr_bfp.md).           |
| `beta_sum_i`/`beta_carry_i[0:15]`   | in | 18 each | Per-DP8 `−β` carry-save, from [pe_array_beta_sqr_bfp](./pe_array_beta_sqr_bfp.md).             |
| `const_dp8_i[0:15]`          | in  | 18 each | Per-DP8 signed constant `C_j`, from [const_sqr_bfp](./const_sqr_bfp.md).                              |
| `neg_i[5:0]`                 | in  | 6       | Per-block negate (modes 10/11): `neg_i[n]` complements L0 node `n`'s lo mantissa bundle.              |
| `zero_i[0:15]`               | in  | 1 each  | Per-DP8 idle-zero: gates that DP8's `−α`/`−β`/`C` to a real 0 (see [Idle clean-zero](#idle-clean-zero)). |
| `exp_a_dp8_i[0:15]`          | in  | 6 each  | Per-DP8 `e_A`, from [disp_array_exp_a_sqr_bfp](./disp_array_exp_a_sqr_bfp.md).                        |
| `exp_b_dp8_i[0:15]`          | in  | 6 each  | Per-DP8 `e_B`, from [disp_array_exp_b_sqr_bfp](./disp_array_exp_b_sqr_bfp.md).                        |
| `sel_shift_i[2:0]`           | in  | 1 each  | Per-level radix-shift enable (`[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`).                        |
| `en_level_i[2:0]`            | in  | 1 each  | Operand-isolation enable per tree branch (`[0]`=L0→L1, `[1]`=L1→L2, `[2]`=L2→L3); masks below the tap.|
| `l0_sum_o`/`l0_carry_o[0:7]` | out | 19 each | L0 data taps (carry-save, `2·P`).                                                                    |
| `l0_exp_o[0:7]`              | out | 7 each  | L0 exponent taps (subtree scale).                                                                    |
| `l1_sum_o`/`l1_carry_o[0:3]` / `l1_exp_o[0:3]` | out | 30 / 7 | L1 data + exponent taps.                                                            |
| `l2_sum_o`/`l2_carry_o[0:1]` / `l2_exp_o[0:1]` | out | 38 / 7 | L2 data + exponent taps.                                                            |
| `l3_sum_o`/`l3_carry_o` / `l3_exp_o`           | out | 39 / 7 | L3 data + exponent tap.                                                             |

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

The datapath is: **16 [dp_8_sqr](./dp_8_sqr.md) cores + 16 `add_n` exponents → per-DP8 idle gate → L0 combine (6 `comp_n` block-negates → [align_cell_bfp](./align_cell_bfp.md) → 14:2 CPR) → [pe_array_bfp](./pe_array_bfp.md)'s L1/L2/L3 tree + exponent max-tree → carry-save + exponent taps at each level.** L1–L3 are [pe_array_bfp](./pe_array_bfp.md) verbatim; this page covers the square-specific L0 and the width/signedness deltas.

### The L0 combine (the crux)

Each of the 8 L0 nodes crosses two DP8s — `CX0 = 4·(n/2)+n%2` (hi) and `CX1 = CX0+2` (lo), the same crossed pairing as the baseline. For each, it builds a **7-row bundle** `{PE s/c, −α s/c, −β s/c, C}`: rows 0–5 are the three carry-save pairs (PE, `−α`, `−β`), row 6 is the per-DP8 constant `C`:

```systemverilog
assign hi_bundle[0] = dp8_sum[CX0];   assign hi_bundle[1] = dp8_carry[CX0];
assign hi_bundle[2] = alpha_g_sum[CX0]; assign hi_bundle[3] = alpha_g_carry[CX0];
assign hi_bundle[4] = beta_g_sum[CX0];  assign hi_bundle[5] = beta_g_carry[CX0];
assign hi_bundle[6] = const_g[CX0];     // row 6 = C (not complemented)
```

The hi bundle is `<<8` radix-shifted (`shift_n`), the lo bundle is `ext_n`-extended, and one [align_cell_bfp](./align_cell_bfp.md) `#(SIZE_0=7, SIZE_1=7)` aligns the two DP8s to `max(E_CX0, E_CX1)` and exports that scale as `l0_exp[n]`. Its 14-row output feeds a single **14:2 [cpr_w_n](./cpr_w_n.md)**, which sums all 14 rows — the two `PE − α − β + C` combines **and** the cross-merge — into one carry-save `2·P` pair:

```systemverilog
align_cell_bfp #(.WIDTH(L0_WIDTH), .SIZE_0(NUM_ROW), .SIZE_1(NUM_ROW),
                 .EXP_WIDTH(EXP_WIDTH), .IS_SIGNED(1'b1)) align_cell_bfp_i ( ... .exp_o(l0_exp[n]) );
cpr_w_n #(.IN_WIDTH(L0_WIDTH), .IN_SIZE(NUM_CPR), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
    .in_i(cpr_in), .sum_o(l0_sum[n]), .carry_o(l0_carry[n])
);
```

The `EXT = 0` / 26-bit L0 CPR is verified sufficient — the `PE − α − β` cancellation resolves inside 26 bits, corner-tested ([BFP_imp.md](../../doc/BFP_imp.md) §9, gate 4).

### The relocated block negate

Modes 10/11 negate a subset of DP8 blocks — always the lo (`CX1`) operand of L0 nodes 0–5. Because the α/β generators are **neg-agnostic** (always `−α`/`−β`), the sign flip is done here by one `comp_n` per L0 node 0–5, on the **whole 6-row lo mantissa bundle** `{PE, −α, −β}` (rows 0–5), *before* the align — the constant row 6 is **not** complemented:

```systemverilog
if (n < NUM_NEG) begin : gen_comp
    comp_n #(.WIDTH(DP8_WIDTH), .SIZE(NUM_MANT)) comp_n_i (   // NUM_MANT = 6
        .in_i(lo_mant_raw), .neg_i(neg_i[n]), .out_o(lo_mant)
    );
end
```

Complementing the mantissa bundle flips `{PE, −α, −β}` to `{−PE, +α, +β}`, so after the combine the block contributes `−(PE − α − β) = −2·P`. The constant is left alone because [const_sqr_bfp](./const_sqr_bfp.md) supplies the **negated** per-DP8 constant (`2 − C_cent`) for those blocks, landing `C` correct after the flip. Nodes 6/7 have no `comp_n` (their DP8s are never negated), which is why `neg_i` is **6 bits**. Mode 12 (`C16C16`) does not appear here — its Im-part negation is done in software by the caller.

### Idle clean-zero

An idle DP8's generators still emit `−2` each and the constant its `+4` deferral — summing to value 0, but a **redundant** carry-save pair that floors to `−1` when an idle-*only* subtree is exponent-aligned against active data (hit at mode 6's L3 merge). So `pe_array_sqr_bfp` gates the `−α`/`−β`/`C` contributions of an idle DP8 to a real 0 (the PE square-sum is already clean), making the whole idle leaf a true carry-save zero:

```systemverilog
assign alpha_g_sum[i] = zero_i[i] ? '0 : alpha_sum_i[i];   // and alpha_g_carry, beta_g_*, const_g
```

This is why [const_sqr_bfp](./const_sqr_bfp.md) needs **no** idle-gate of its own — the PE array masks it.

### Exponents and the max-tree

Each DP8's scale is formed by a 6+6→7 `add_n`, `E_j = e_A,j + e_B,j`, so `EXP_WIDTH = 7` holds the product-domain scale exactly:

```systemverilog
add_n #(.WIDTH(EXP_IN_WIDTH), .CARRY(1)) add_n_exp_i (
    .in_0_i({1'b0, exp_a_dp8_i[i]}), .in_1_i({1'b0, exp_b_dp8_i[i]}), .cin_i(1'b0),
    .out_o(exp_dp8[i][EXP_IN_WIDTH-1:0]), .cout_o(exp_dp8[i][EXP_IN_WIDTH])
);
```

L0 aligns each crossed pair and forwards `max(E_CX0, E_CX1)`. L1 does **no** data align but forwards the max exponent via a `sub_n_bfp` sign + `mux_n`; L2/L3 align again with [align_cell_bfp](./align_cell_bfp.md). All of this — and the per-level exponent taps — is [pe_array_bfp](./pe_array_bfp.md) verbatim.

### Widths and taps

The square-sum leaves are 18-bit, but the **combined** `2·P` is far narrower than a raw square-sum (the `PE − α − β` cancellation collapses it), so the node widths equal [pe_array_sqr](./pe_array_sqr.md) (26/30/38/39). The taps carry `2·P`, one bit wider than baseline BFP:

```systemverilog
localparam int L0_TAP_WIDTH = 19;   // = baseline-BFP (18) + 1  (carries 2·P)
localparam int L1_TAP_WIDTH = 30;
localparam int L2_TAP_WIDTH = 38;
localparam int L3_TAP_WIDTH = 39;
```

Taps are sliced from the low bits of each node exactly as the baseline. **L0 is the only registered stage** — two `reg_n` banks (data at full 26-bit node width, not the 19-bit tap) plus one `reg_n` for the L0 exponent, so the R16 modes' `<<8` intermediate reaches L1 without truncation. L1/L2/L3 and the exponent max-tree are combinational — one clock through the whole tree. Reading a mode's result at the right level/tap follows [pe_array_bfp](./pe_array_bfp.md) (8→L0, 4→L1, 2→L2, 1→L3; a complex output reads one level shallower).

These widths are verified sign-consistent across all 11 modes under corner-biased operands by [tb_pe_array_sqr_bfp.sv](../../tb/tb_pe_array_sqr_bfp.sv) — Pass A (equal exponents) bit-exact to `2·A·B`, Pass B (distinct legal BFP exponents) exponent-exact plus a per-tap truncation window — including the whole-lo-bundle negate (10/11) and the `zero_i` idle clean-zero.

Source: [pe_array_sqr_bfp.sv](../../rtl/pe_array_sqr_bfp.sv) — Testbench: [tb_pe_array_sqr_bfp.sv](../../tb/tb_pe_array_sqr_bfp.sv) — Diagram: [pe_array_sqr_bfp](../../doc/diagrams/pe_array_sqr_bfp.excalidraw)
