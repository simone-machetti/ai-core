# PE Array (Square)

`pe_array_sqr` — the square variant of [pe_array](./pe_array.md). Same 4-level crossed carry-save reduction tree (8 → 4 → 2 → 1, a tap at every level), but the 16 DP8 cores are [dp_8_sqr](./dp_8_sqr.md) (18-bit **unsigned** square-sum) instead of [dp_8](./dp_8.md), and the complex-mode block negate has **relocated here** from the B dispatcher as a per-block [comp_n](./comp_n.md). Fixed to the PE.

## Purpose

Each [dp_8_sqr](./dp_8_sqr.md) produces one length-8 **square-sum** `S_DP8` in 18-bit carry-save form (operands arrive pre-centered from [disp_array_a_sqr](./disp_array_a_sqr.md) / [disp_array_b_sqr](./disp_array_b_sqr.md), so there is no `is_signed` here). The tree sums the 16 blocks with the per-mode radix weights, exactly as the baseline, and leaves the result carry-save for `acc_array_sqr` to resolve and reconstruct (`Result = ½(PE − α − β + C)`). Two things differ from the baseline tree, and both are local:

1. **The block negate** (modes 10/11) is done in the tree by one's-complementing a whole DP8's carry-save pair — see [The relocated negate](#the-relocated-negate).
2. **Wider leaves, narrower guard** — a square-sum has no cancellation, so it grows one bit faster than the baseline dot product; the widths shift accordingly — see [Width growth and the taps](#width-growth-and-the-taps).

## Parameters

None — fixed to the PE configuration; the shape is baked in as `localparam`s. The key ones (contrast with [pe_array](./pe_array.md)):

| Localparam                    | Value             | Meaning                                                        |
| ----------------------------- | ----------------- | -------------------------------------------------------------- |
| `NUM_DP8`                     | 16                | `dp_8_sqr` cores driving the tree.                             |
| `NUM_L0`/`NUM_L1`/`NUM_L2`    | 8 / 4 / 2         | node count at L0/L1/L2 (L3 is a single node).                  |
| `NUM_NEG`                     | 6                 | `comp_n` block-negate gates (one per L0 node 0–5).             |
| `DP8_WIDTH`                   | 18                | each `dp_8_sqr` carry-save row width (unsigned square-sum).    |
| `SH0`/`SH1`/`SH2`             | 8 / 4 / 8         | per-level left-shift amount (L0/L1/L2; L3 has no shift).       |
| `L3_EXT`                      | 1                 | extra guard growth at L3 (the merge without a shift).          |
| `L0_WIDTH`…`L3_WIDTH`         | 26 / 30 / 38 / 39 | internal node width at each level (what feeds the next level). |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | 19 / 30 / 38 / 39 | tap width exported to the accumulator at each level.           |

Signedness: everything runs signed (`IS_SIGNED = 1'b1`) **except the L0 `shift_n`** — see [Signedness](#signedness-l0-hi-is-unsigned). Every `cpr_w_n` runs `EXT = 0` except L3, which runs `EXT = L3_EXT = 1`.

## Interface

| Signal                       | Dir | Width   | Description                                                             |
| ---------------------------- | --- | ------- | ----------------------------------------------------------------------- |
| `clk_i`                      | in  | 1       | Clock.                                                                  |
| `rst_ni`                     | in  | 1       | Asynchronous active-low reset.                                          |
| `a_dp8_i[0:15]`              | in  | 64 each | A operand per DP8 (8 × pre-centered int8), from `disp_array_a_sqr`.     |
| `b_dp8_i[0:15]`              | in  | 32 each | B operand per DP8 (8 × pre-centered int4), from `disp_array_b_sqr`.     |
| `neg_i[5:0]`                 | in  | 6       | **NEW** — per-block negate: `neg_i[n]` complements L0 node `n`'s lo.    |
| `sel_shift_i[2:0]`           | in  | 1 each  | Per-level shift enable: `[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`. |
| `l0_sum_o`/`l0_carry_o[0:7]` | out | 19 each | L0 taps (carry-save).                                                   |
| `l1_sum_o`/`l1_carry_o[0:3]` | out | 30 each | L1 taps.                                                                |
| `l2_sum_o`/`l2_carry_o[0:1]` | out | 38 each | L2 taps.                                                                |
| `l3_sum_o`/`l3_carry_o`      | out | 39      | L3 tap.                                                                 |

`is_signed_a_i`/`is_signed_b_i` are **gone** (the dispatcher already centered the operands); `neg_i[5:0]` is **added**. Every tap is a carry-save pair (`sum + carry`); the tree never resolves.

## Instantiation

```systemverilog
pe_array_sqr pe_array_sqr_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .b_dp8_i(b_dp8),
    .neg_i(neg), .sel_shift_i(sel_shift),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry),
    .l1_sum_o(l1_sum), .l1_carry_o(l1_carry),
    .l2_sum_o(l2_sum), .l2_carry_o(l2_carry),
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry)
);
```

## Internal logic

The datapath is: **16 `dp_8_sqr` cores → 6 `comp_n` block-negates → a 4-level crossed carry-save tree of 15 compressors (8 + 4 + 2 + 1) → carry-save taps at each level.** Everything below the DP8 leaves is *identical in structure* to [pe_array](./pe_array.md) — same crossed L0 pairing (`CX0 = 4·(n/2) + n%2`, `CX1 = CX0 + 2`), same shift/extend/compress node shape, same single L0 register stage, same tap slicing. This page covers only the deltas; see [pe_array](./pe_array.md) for the shared tree anatomy.

### The relocated negate

Modes 10/11 (complex) negate a subset of DP8 blocks. Those blocks are **always** the lo (`CX1`) operand of L0 nodes 0–5, i.e. DP8 `{2, 3, 6, 7, 10, 11}` (the union of the two modes' negated sets). So the negate is done by one `comp_n` per L0 node 0–5, on the lo pair, **before** its `ext_n`:

```systemverilog
if (n < NUM_NEG) begin : gen_comp
    comp_n #(.WIDTH(DP8_WIDTH), .SIZE(2)) comp_n_i (
        .in_i(lo_raw), .neg_i(neg_i[n]), .out_o(lo_in)
    );
end else begin : gen_nocomp
    assign lo_in[0] = lo_raw[0];
    assign lo_in[1] = lo_raw[1];
end
```

Nodes 6 and 7 have no `comp_n` (their DP8s are never negated), which is why `neg_i` is **6 bits, not 16** — one per possibly-negated node, not one per DP8. Complementing both rows makes the pair resolve to `−S_DP8 − 2`; the tree sign-extends `~S_DP8` to `−S_DP8 − 1` per row and the deferred `+2` per block rides into `acc_array_sqr`'s `C`. `neg_i[n]` maps directly onto the `comp_n` of L0 node `n`.

| Mode       | `neg_i[5:0]` | Negated L0 nodes → DP8s |
| ---------- | ------------ | ----------------------- |
| 10         | `110011`     | 0,1,4,5 → DP8 2,3,10,11 |
| 11         | `001111`     | 0,1,2,3 → DP8 2,3,6,7   |
| all others | `000000`     | none                    |

Mode 12 (`C16C16`) does **not** appear here: its Im-part negation is done in software by the caller (it stores `−b_im`), so no hardware negate — see [square_imp.md](../../doc/formulas/square/square_imp.md) §4.

### Signedness (L0 hi is unsigned)

Because the negated legs carry `~S_DP8` (a sign-mixing value) and everything downstream must sign-extend correctly, the whole tree runs **signed** — with one exception. The L0 `shift_n` acts on the **hi** (`CX0`) operand, and the hi DP8s are *never* negated, so `S_DP8 ≥ 0` there and sign-extend equals zero-extend. That `shift_n` runs `IS_SIGNED = 1'b0` (unsigned); the `ext_n` on the (possibly-complemented) lo, and every `cpr_w_n`/`shift_n` from L0's compressor onward, run signed:

```systemverilog
shift_n #(.WIDTH(DP8_WIDTH), .SIZE(2), .SHIFT(SH0), .IS_SIGNED(1'b0)) shift_n_i ( ... );  // hi: unsigned
ext_n   #(.WIDTH(DP8_WIDTH), .SIZE(2), .EXT(SH0),   .IS_SIGNED(1'b1)) ext_n_i   ( ... );  // lo: signed
```

This matches the diagram's `26-bit U` (the L0 hi shift path) vs `26-bit S` (the signed node).

### Width growth and the taps

A `dp_8_sqr` output is a **sum of squares** — no terms cancel — so its value fills the full 16 bits (`S_DP8 ≤ 34816`), one bit more than the baseline dot product. `dp_8_sqr` is therefore 18-bit (16 value + **2 guard**), vs the baseline's 20-bit (16 value + 4 guard). The 2 guard bits ride through L0–L2 with `EXT = 0`, but **L3 merges the two halves with no shift**, so its value doubles (gains a bit) without any width added by a shift — it takes `L3_EXT = 1` to keep the 2-guard margin:

```systemverilog
localparam int L0_WIDTH = DP8_WIDTH + SH0;    // 18 + 8 = 26
localparam int L1_WIDTH = L0_WIDTH + SH1;     // 26 + 4 = 30
localparam int L2_WIDTH = L1_WIDTH + SH2;     // 30 + 8 = 38
localparam int L3_EXT   = 1;
localparam int L3_WIDTH = L2_WIDTH + L3_EXT;  // 38 + 1 = 39
```

**Node and tap widths (baseline vs square).** The tap holds the widest *reading* mode's value + 2 compressor guard bits; nodes hold the widest *pass-through* value and feed the next level:

| Level | baseline node | baseline tap | **square node** | **square tap** |
| ----- | ------------- | ------------ | --------------- | -------------- |
| DP8   | 20            | —            | **18**          | —              |
| L0    | 28            | 18           | **26**          | **19**         |
| L1    | 32            | 29           | **30**          | **30**         |
| L2    | 40            | 37           | **38**          | **38**         |
| L3    | 40            | 38           | **39**          | **39**         |

The widest value is mode 8 (R16R16) at L3: ≈2³⁶·¹⁹ → 37-bit, inside the 39-bit node/tap (2 guard). Unlike the baseline, at L1/L2/L3 the **tap equals its node** — the square value uses nearly the whole node, so there is no wider pass-through to strip off; only L0 truncates the mode-8 pass-through it never reads (node 26 → tap 19). The taps are sliced from the low bits of each node exactly as in the baseline:

```systemverilog
assign l0_sum_o[n] = l0_sum_q[n][L0_TAP_WIDTH-1:0];   // low 19 of 26
assign l1_sum_o[j] = l1_sum[j][L1_TAP_WIDTH-1:0];     // 30 of 30
assign l2_sum_o[k] = l2_sum[k][L2_TAP_WIDTH-1:0];     // 38 of 38
assign l3_sum_o    = l3_sum_w[L3_TAP_WIDTH-1:0];      // 39 of 39
```

These widths are verified sign-consistent across all 11 modes under corner-biased operands by [tb_pe_array_sqr](../testbenches/tb_pe_array_sqr.md) — including the negate (10/11), the idle-zero (5/6), and the widest tree (8).

### Pipelining

Unchanged from the baseline: **L0 is the only registered stage**, two `reg_n` banks capturing the L0 nodes at full 26-bit width (not the 19-bit tap) so the R16 modes' `<<8` intermediate reaches L1 without truncation. L1/L2/L3 are combinational — one clock through the whole tree.

### Reading a mode's result (which level / tap)

Identical to the baseline: a mode reads at the level whose node count equals its parallel-output count — 8 → L0, 4 → L1, 2 → L2, 1 → L3; a complex output occupies two adjacent nodes so it reads one level shallower. See [pe_array](./pe_array.md#reading-a-modes-result-which-level--tap) for the full `TAP_LEVEL` table.

Source: [pe_array_sqr.sv](../../rtl/pe_array_sqr.sv) — Testbench: [tb_pe_array_sqr.sv](../../tb/tb_pe_array_sqr.sv) — Diagram: [pe_array_sqr](../../doc/diagrams/pe_array_sqr.excalidraw)
