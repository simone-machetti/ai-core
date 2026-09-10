# PE Array (NR4SD BFP)

`pe_array_nr4sd_bfp` — the [pe_array_bfp](./pe_array_bfp.md) tree with [dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md) leaves. Same 4-level crossed carry-save reduction, same 11 in-tree `align_cell_bfp` aligners, same exponent max-tree, same taps at every level — and, unlike the bit-plane builds, the **same widths**: `DP8_WIDTH` stays 20, so the tree body below the leaves is byte-for-byte baseline-BFP's. Only the DP8 cores and their B operand contract change.

## Purpose

The point of this array is what the leaf swap does **not** touch. [dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md) returns the same 20-bit sign-consistent carry-save row as [dp_8](./dp_8.md), so every node width (28/32/40/40), every tap (18/29/37/38) and every guard margin is [pe_array_bfp](./pe_array_bfp.md)'s, and [acc_array_bfp](./acc_array_bfp.md) is reused as-is rather than forked the way the bit-plane builds had to fork it into [acc_array_bpl_bfp](./acc_array_bpl_bfp.md).

The consequence shows in the intra-PE split: the bit-plane-B build buys a larger core saving but pays a 22-bit-row tree penalty for it; this build's saving is smaller, but it hands the tree nothing to absorb:

| section              | baseline-BFP | bit-plane B       | NR4SD                 |
| -------------------- | ------------ | ----------------- | --------------------- |
| DP8 array (16 cores) | 3091.57 µm²  | 1871.61 (−39.5 %) | **2353.97 (−23.9 %)** |
| CPR tree             | 1698.32 µm²  | 1858.89 (+9.5 %)  | **1698.32 (0.0 %)**   |

The CPR-tree figure is byte-identical to baseline-BFP's — the boundary-preserved synthesis lands on the same 1698.32 µm². See [Intra-PE Area](../experiments/syn_pe_area.md).

What does change is how B arrives. The recoders ([nr4sd_r4](./nr4sd_r4.md)) are hoisted into the column dispatcher [disp_array_b_nr4sd_bfp](./disp_array_b_nr4sd_bfp.md), so each DP8 receives B as **two digit buses**: `b_nr4sd_dp8` (8 lanes × 2-bit NR4SD⁺ code, the weight-1 digit, consumed by an [nr4sd_r4_cell](./nr4sd_r4_cell.md)) and `b_booth_dp8` (8 lanes × 3-bit Booth window, the weight-4 digit, consumed by a [booth_r4_cell](./booth_r4_cell.md)) — 5 bits per lane, 40 per DP8, against raw B's 4 and 32 (+25 %; the superseded 3-digit build needed 48). Two partial products per lane instead of Booth's three.

## Parameters

None — fixed to the PE configuration (`EXP_WIDTH = EXP_IN_WIDTH + 1 = 7` holds `e_A + e_B` of two 6-bit format exponents exactly).

| Localparam                                | Value       | Meaning                                                        |
| ----------------------------------------- | ----------- | -------------------------------------------------------------- |
| `NUM_DP8`                                 | 16          | Dot-product cores.                                             |
| `LANES` / `IN_WIDTH_A`                    | 8 / 8       | Lanes per DP8; raw int8 A lanes (unchanged).                   |
| `CODE_WIDTH` / `BSEL_WIDTH`               | 2 / 3       | **NEW** — NR4SD⁺ code and Booth window per lane.               |
| `B_NR4SD_DP8_WIDTH` / `B_BOOTH_DP8_WIDTH` | 16 / 24     | **NEW** — the two B digit buses per DP8.                       |
| `DP8_WIDTH`                               | 20          | Carry-save row from each core — **unchanged**.                 |
| `SH0` / `SH1` / `SH2`                     | 8 / 4 / 8   | Runtime-selected level shifts.                                 |
| `L0..L3_WIDTH`                            | 28/32/40/40 | Node widths — unchanged, no guard bit.                         |
| `L0..L3_TAP_WIDTH`                        | 18/29/37/38 | Exported tap widths — unchanged, what `acc_array_bfp` expects. |
| `EXP_IN_WIDTH` / `EXP_WIDTH`              | 6 / 7       | Dispatched format exponent; product-domain scale.              |

## Interface

Against [pe_array_bfp](./pe_array_bfp.md), the operand contract changes on the B side and nothing else:

| Signal                                 | Dir | Width          | Description                                                        |
| -------------------------------------- | --- | -------------- | ------------------------------------------------------------------ |
| `a_dp8_i[0:15]`                        | in  | 64             | 8 × 8-bit raw A lanes, from `disp_array_a` (unchanged).            |
| `b_nr4sd_dp8_i[0:15]`                  | in  | 16             | **NEW** — 8 × 2-bit NR4SD⁺ codes (weight-1 digit).                 |
| `b_booth_dp8_i[0:15]`                  | in  | 24             | **NEW** — 8 × 3-bit Booth windows (weight-4 digit).                |
| `is_signed_a_i[0:15]`                  | in  | 1              | Per-DP8 A signedness — the only signedness signal left in a leaf.  |
| `exp_a_dp8_i` / `exp_b_dp8_i`          | in  | 6              | Per-DP8 6-bit format exponents.                                    |
| `sel_shift_i` / `en_level_i`           | in  | 3              | Level shift select; per-level register enable.                     |
| `l0..l3_sum_o` / `_carry_o` / `_exp_o` | out | 18/29/37/38, 7 | Carry-save pair + 7-bit scale at every level.                      |

**No `is_signed_b_i`** — consumed in [disp_array_b_nr4sd_bfp](./disp_array_b_nr4sd_bfp.md), where it reads as "this DP8 holds the top nibble of its element" and selects the cross-nibble carry. **No `b_dp8_i`** either: raw B never reaches the PE. This is the mirror of [pe_array_bpl_b_bfp](./pe_array_bpl_b_bfp.md), where `is_signed_a_i` is the one that disappears.

## Instantiation

```systemverilog
for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
    logic [IN_WIDTH_A-1:0] a_lane       [0:LANES-1];
    logic [CODE_WIDTH-1:0] b_nr4sd_lane [0:LANES-1];
    logic [BSEL_WIDTH-1:0] b_booth_lane [0:LANES-1];
    for (ln = 0; ln < LANES; ln++) begin : gen_lane
        assign a_lane[ln]       = a_dp8_i[i][ln*IN_WIDTH_A +: IN_WIDTH_A];
        assign b_nr4sd_lane[ln] = b_nr4sd_dp8_i[i][ln*CODE_WIDTH +: CODE_WIDTH];
        assign b_booth_lane[ln] = b_booth_dp8_i[i][ln*BSEL_WIDTH +: BSEL_WIDTH];
    end
    dp_8_nr4sd_bfp dp_8_nr4sd_bfp_i (
        .a_i          (a_lane),
        .b_nr4sd_i    (b_nr4sd_lane),
        .b_booth_i    (b_booth_lane),
        .is_signed_a_i(is_signed_a_i[i]),
        .sum_o        (dp8_sum[i]),
        .carry_o      (dp8_carry[i])
    );
end
```

## Internal logic

Unchanged from [pe_array_bfp](./pe_array_bfp.md): a per-DP8 [add_n](./add_n.md) forms the scale `e_A + e_B` (6 + 6 → 7, exact); the L0 cells consume the crossed pair (`CX0 = 4·(n/2) + n%2`, `CX1 = CX0 + 2`) and emit the L0 node exponents, registered alongside the L0 mantissa registers; per L1 node the max of its two L0 exponents is forwarded ([sub_n_bfp](./sub_n_bfp.md) + [mux_n](./mux_n.md), no shifter); L2 and L3 continue the max tree. Every tap exports its exponent next to the carry-save pair. The exponent dispatchers meet only here — A per grid **row**, B per grid **column** — and an idle DP8 must arrive with **both** sides gated to zero so its scale never wins a max.

### What a leaf hands up

Each lane multiplies A by `d₀ + 4·d₁ ∈ [−9, +10]` — the nibble **read as signed** plus the cross-nibble carry the dispatcher imports (`c_in[i] = ~is_signed_b[i+1] & MSB(gated nibble of DP8 i+1)`, none into DP8 `4q+3`). A DP8 holding a **lower** nibble of a wider element therefore returns a partial that is `16·b₃·A` too small per lane and is not a value on its own; the DP8 holding the nibble above carries the matching `+b₃·A`, and the ×16 weight of the merge that recombines the two halves of one element — the L1 merge, in every mode — cancels them (see the [derivation](../../doc/formulas/encodings/nr4sd_2pp.tex)). Every mode that slices B reads its tap at L1 or above; the only L0 reader, mode 1, multiplies whole int4 B, where no link exists. The cancellation is exact because a partial of the same weight is what the L1 compressor adds, not something the aligners have to reconstruct.

### The tree body is baseline-BFP's

Because the leaf keeps `DP8_WIDTH = 20`, the aligner and compressor at every node instantiate at exactly the widths of [pe_array_bfp](./pe_array_bfp.md) — no guard bit, `EXT = 0` on every `cpr_w_n`:

```systemverilog
align_cell_bfp #(
    .WIDTH    (DP8_WIDTH+SH0),
    .SIZE_0   (2),
    .SIZE_1   (2),
    .EXP_WIDTH(EXP_WIDTH),
    .IS_SIGNED(1'b1)
) align_cell_bfp_i (
    .in_0_i    (hi_sh),
    .exp_0_i   (exp_dp8[CX0]),
    .in_1_i    (lo_ext),
    .exp_1_i   (exp_dp8[CX1]),
    .chain_en_i(1'b0),
    .chain_0_i (zero_ch),
    .chain_1_i (zero_ch),
    .chain_0_o (),
    .chain_1_o (),
    .out_o     (cpr_in),
    .exp_o     (l0_exp[n])
);

cpr_w_n #(.IN_WIDTH(DP8_WIDTH+SH0), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
    .in_i(cpr_in), .sum_o(l0_sum[n]), .carry_o(l0_carry[n])
);
```

The bit-plane leaves pad to 22 bits and drag a guard bit through L0 and L1 (nodes 31/36/44/44, taps 18/36/40/40); this leaf does not, and that is the whole reason the accumulator needs no fork.

### Where the sliced-B partials meet the aligners

At L0 the two halves of a B element sit in **different nodes** — DP8 `4q` pairs with `4q+2`, `4q+1` with `4q+3` — so the `+b₃·A` and `−16·b₃·A` terms each cross an L0 aligner before L1 recombines them. With equal exponents every aligner is transparent and the cancellation at L1 is exact, so every tap carries the same value as `pe_array_bfp`'s. With **unequal exponents inside an L0 node** — which the mode tables allow only in modes 2 and 6 — each term is truncated on its own side, and the L1 result differs from the three-partial-product tree at the LSB level, within the same error bound. All other modes, and all modes with equal exponents, are value-identical.

## Verification

[tb_pe_array_nr4sd_bfp](../testbenches/tb_pe_array_nr4sd_bfp.md) runs the array downstream of the real dispatchers with the baseline [pe_array](./pe_array.md) alongside as the integer reference, over 11 modes × two exponent passes. **11/11, 0 mismatches.** As in the bit-plane builds the criterion is the **resolved tap value**, not the bit pattern: NR4SD and Booth spell the same `b` with different digits, so the carry-save encoding legitimately differs. The L0 taps are compared only in the whole-int4 modes (1, 5): with a sliced B a lower-nibble DP8 legitimately differs at L0 until L1 recombines it.

Source: [pe_array_nr4sd_bfp.sv](../../rtl/pe_array_nr4sd_bfp.sv) — Testbench: [tb_pe_array_nr4sd_bfp.sv](../../tb/tb_pe_array_nr4sd_bfp.sv) — Diagram: [pe_array_nr4sd_bfp](../../doc/diagrams/pe_array_nr4sd_bfp.excalidraw) — Derivation: [nr4sd_2pp.tex](../../doc/formulas/encodings/nr4sd_2pp.tex)
