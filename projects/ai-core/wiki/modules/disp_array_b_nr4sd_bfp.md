# Dispatch Array B (NR4SD BFP)

`disp_array_b_nr4sd_bfp` — the [disp_array_b](./disp_array_b.md) variant that also produces the operands [dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md) needs. Routing, splitting and gating are unchanged: one 4→1 block select per pair, a fixed high/low split, one carry-chained [gate_b_n](./gate_b_n.md) per half, all shared by a whole grid column. What is added sits **after** the gates: the cross-nibble link and one [nr4sd_r4](./nr4sd_r4.md) recoder per nibble per DP8, so the column broadcasts two digit buses per DP8 instead of raw B.

This is the B-side counterpart of [disp_array_a_bpl_b_bfp](./disp_array_a_bpl_b_bfp.md): there the hoisted function of one operand is A's pair sums in the per-**row** dispatch; here it is B's recoding in the per-**column** dispatch — and, unlike the bit-plane build, the DP8 is left with a plain radix-4 multiplier.

## Purpose

A radix-4 recoder is a function of **B alone**, so it does not belong inside a PE:

| term                      | cost                     | scales as |
| ------------------------- | ------------------------ | --------- |
| recoders                  | `N` columns × 16 DP8 × 8 | **O(N)**  |
| digit cells + compression | `N²` PEs                 | **O(N²)** |

Recoding in the dispatcher is also what makes the two-partial-product scheme possible: the recoder there can see the **neighbouring** nibble, which the cross-nibble carry needs, whereas a recoder inside the DP8 only ever sees its own lane.

The dispatcher grows `466.327 → 526.907` µm² (**+13.0 %**; the three-digit build was 558.414) and its unit power `0.101 → 0.116` mW (**+14.9 %**), while the 16-core DP8 array of every PE falls `3091.57 → 2353.97` µm². See [Synthesis Area](../experiments/syn_area.md) and [Intra-PE Area](../experiments/syn_pe_area.md).

## Parameters

None — fixed to the grid's dispatch configuration.

| Localparam                                    | Value      | Meaning                                                  |
| --------------------------------------------- | ---------- | -------------------------------------------------------- |
| `NUM_BLK` / `BLK_WIDTH`                       | 4 / 64     | B operand blocks in the 256-bit word.                    |
| `NUM_PAIR` / `NUM_DP8`                        | 8 / 16     | DP8 pairs; DP8s fed (two per pair).                      |
| `B_DP8_WIDTH` / `B_ELEM_WIDTH` / `NUM_B_ELEM` | 32 / 4 / 8 | Raw B half per DP8, one int4 nibble, nibbles per DP8.    |
| `OP_WIDTH`                                    | 2          | B-gate op code.                                          |
| `CODE_WIDTH` / `BOOTH_SEL_WIDTH`              | 2 / 3      | **NEW** — NR4SD⁺ code and Booth window per nibble.       |
| `B_NR4SD_DP8_WIDTH` / `B_BOOTH_DP8_WIDTH`     | 16 / 24    | **NEW** — packed per-DP8 digit buses.                    |

## Interface

| Signal                | Dir | Width | Description                                                        |
| --------------------- | --- | ----- | ------------------------------------------------------------------ |
| `clk_i` / `rst_ni`    | in  | 1     | Clock (column-gated), asynchronous active-low reset.               |
| `pe_in_b_i`           | in  | 256   | The column's B operand word (4 blocks × 64).                       |
| `sel_b_i[0:7]`        | in  | 2     | Per-pair 4→1 block select, from `ctrl`.                            |
| `ctr_l_i[0:7]`        | in  | 2     | Odd-DP8 (low half) gate op: pass / zero / negate / negate-carry.   |
| `ctr_h_i[0:7]`        | in  | 2     | Even-DP8 (high half) gate op.                                      |
| `is_signed_b_i[0:15]` | in  | 1     | **NEW** — per-DP8 B signedness, from `ctrl` — **consumed here**.   |
| `b_nr4sd_dp8_o[0:15]` | out | 16    | **NEW** — eight 2-bit NR4SD⁺ codes, lane `e` at `[2e +: 2]`.       |
| `b_booth_dp8_o[0:15]` | out | 24    | **NEW** — eight 3-bit Booth windows, lane `e` at `[3e +: 3]`.      |

The 256-bit operand is registered on input; routing, gating, linking and recoding are combinational and the result is broadcast to the column's PEs. `ctrl` is unchanged: it still emits `is_signed_b` per DP8, only its consumer has moved.

## Instantiation

```systemverilog
disp_array_b_nr4sd_bfp disp_array_b_nr4sd_bfp_i (
    .clk_i        (clk_b),
    .rst_ni       (rst_ni),
    .pe_in_b_i    (in_b_i[c]),
    .sel_b_i      (sel_b),
    .ctr_l_i      (ctr_l),
    .ctr_h_i      (ctr_h),
    .is_signed_b_i(is_signed_b),
    .b_nr4sd_dp8_o(b_nr4sd_dp8_col[c]),
    .b_booth_dp8_o(b_booth_dp8_col[c])
);
```

## Internal logic

Read top-to-bottom it is: reshape → register → per-pair B mux → split → gate → **link → recode** → pack. The first five stages are [disp_array_b](./disp_array_b.md) verbatim; the only change there is that the gated nibbles are gathered into one per-DP8 array so the two new stages can index them by DP8:

```systemverilog
for (e = 0; e < NUM_B_ELEM; e++) begin : gen_gather
    assign nib_gated[2*p+0][e] = bhi_gated[e];
    assign nib_gated[2*p+1][e] = blo_gated[e];
end
```

Even DP8 `2p` still carries the **high** nibble, odd DP8 `2p+1` the **low** one.

### The cross-nibble link, after the gate

Every nibble is recoded as **signed** (see [nr4sd_r4](./nr4sd_r4.md)), so a nibble that is a lower slice of a wider element comes out `16·b₃` too small, and the nibble above repays it through its carry-in. The link is one AND per lane:

```systemverilog
for (i = 0; i < NUM_DP8; i++) begin : gen_link
    if (i % 4 == 3) begin : gen_bottom
        for (e = 0; e < NUM_B_ELEM; e++) begin : gen_zero
            assign c_in[i][e] = 1'b0;
        end
    end else begin : gen_up
        logic link_en;
        assign link_en = ~is_signed_b_i[i+1];
        for (e = 0; e < NUM_B_ELEM; e++) begin : gen_and
            assign c_in[i][e] = link_en & nib_gated[i+1][e][B_ELEM_WIDTH-1];
        end
    end
end
```

`is_signed_b_i[i]` therefore means **"DP8 `i` holds the top nibble of its element"**: the DP8 above an unsigned (lower) nibble takes that nibble's MSB, the DP8 above a signed (top) nibble takes `0`. The mapping *below-in-significance = next DP8 index* holds in every mode:

| Element | DP8s             | Nibbles        | Links (`c_in` of ← `b₃` of)               |
| ------- | ---------------- | -------------- | ----------------------------------------- |
| int4    | `i`              | whole          | none — `is_signed_b[i] = 1`               |
| int8    | pair `2p, 2p+1`  | H, L           | `2p ← 2p+1`                               |
| int16   | quad `4q … 4q+3` | hh, hl, lh, ll | `4q ← 4q+1`, `4q+1 ← 4q+2`, `4q+2 ← 4q+3` |

The high byte of an int16 sits in the even pair, so `4q+1` (hl) links to `4q+2` (lh) **across the pair boundary**. `4q+3` is always the bottom of its element, so those four DP8s have no link: 12 linked DP8s × 8 lanes = **96 ANDs** per dispatcher. An idle DP8 is a zero nibble, so a link from it is harmless.

The link is taken **after** the gate, from `nib_gated`, because the `b₃` must be that of the value the DP8 actually multiplies — negated in the complex modes, zero for an idle lane.

### One recoder per nibble, after the link

```systemverilog
for (i = 0; i < NUM_DP8; i++) begin : gen_enc
    for (e = 0; e < NUM_B_ELEM; e++) begin : gen_elem
        nr4sd_r4 #(
            .IN_WIDTH_B(B_ELEM_WIDTH)
        ) nr4sd_r4_i (
            .b_i      (nib_gated[i][e]),
            .c_in_i   (c_in[i][e]),
            .b_nr4sd_o(b_nr4sd_dp8_o[i][e*CODE_WIDTH +: CODE_WIDTH]),
            .b_booth_o(b_booth_dp8_o[i][e*BOOTH_SEL_WIDTH +: BOOTH_SEL_WIDTH])
        );
    end
end
```

16 DP8s × 8 nibbles = **128 recoders** per column, each a handful of gates plus wiring, paid `N` times where the baseline pays its Booth recoding inside every one of the `N²` PEs. They must sit downstream of the gates for the same reason as the link: a recoder before the gate would recode the wrong value on the negate and idle modes.

### Bus cost

Each DP8 now receives `8 × (2 + 3) = 40` bits — `b_nr4sd_dp8_o` (16) plus `b_booth_dp8_o` (24) — against raw B's 32, **+25 %**. The three-digit NR4SD⁺ build broadcast 48 (+50 %); hoisting a full three-digit Booth recoder would need 72 (+125 %). Both zero codes are all-zero, so the PE's `en_i` AND-mask idles a DP8 on these buses exactly as it did on raw B.

### Where `is_signed_b` stops

Because the nibbles leave already recoded, per-DP8 B signedness is consumed here and **never reaches the PEs** — which is why [dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md) and [pe_array_nr4sd_bfp](./pe_array_nr4sd_bfp.md) have no `is_signed_b_i` port. `is_signed_a` still travels to the PEs, as in the baseline: A is extended inside the cells. See [top_NxN_nr4sd_bfp](../architectures/top_NxN_nr4sd_bfp.md) for how the grid wires one of these per column.

## Verification

[tb_disp_array_nr4sd_bfp](../testbenches/tb_disp_array_nr4sd_bfp.md) drives this dispatcher and [disp_array_a](./disp_array_a.md) together against a golden model for all 11 modes, with the real per-mode control vectors from `ctrl`'s lookup tables, comparing the recoded outputs **by digit value**. **11/11, 0 mismatches.**

Source: [disp_array_b_nr4sd_bfp.sv](../../rtl/disp_array_b_nr4sd_bfp.sv) — Testbench: [tb_disp_array_nr4sd_bfp.sv](../../tb/tb_disp_array_nr4sd_bfp.sv) — Diagram: [disp_array_b_nr4sd_bfp](../../doc/diagrams/disp_array_b_nr4sd_bfp.excalidraw)
