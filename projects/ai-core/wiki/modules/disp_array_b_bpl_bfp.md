# Dispatch Array B (Bit-Plane BFP)

`disp_array_b_bpl_bfp` — the B-path dispatcher of the bit-plane variant, one per grid column. Routing is [disp_array_b](./disp_array_b.md) unchanged; what is added is one [gate_b_n_bpl_bfp](./gate_b_n_bpl_bfp.md) per DP8, so the column broadcasts **two** operand sets instead of one: the eight per-lane values already resolved to signed 5-bit, and the four pairwise sums at 6 bits.

## Purpose

The bit-plane [dp_8_bpl_bfp](./dp_8_bpl_bfp.md) needs, per lane pair and per bit plane, one of `{0, b₂ⱼ, b₂ⱼ₊₁, b₂ⱼ + b₂ⱼ₊₁}`. The pair sums are a function of **B alone**, so they can be hoisted out of the PE and computed once per grid **column**:

|                    | adders for the pair sums |
| ------------------ | ------------------------ |
| inside each PE     | `N²` × 16 DP8s × 4 sums  |
| in this dispatcher | `N` × 16 DP8s × 4 sums   |

That `N² → N` move is the amortization the whole variant is built on — the same lever the square variant pulls with its α/β generators. It is paid for in dispatcher area (`616.22` vs `466.33` µm², **+32 %**) and bought back `N²` times over in the PE.

The second thing that moves here is **signedness**. Because the gate resolves each nibble to its exact signed value, `is_signed_b_i` is consumed in this module and never reaches the PEs — [pe_array_bpl_bfp](./pe_array_bpl_bfp.md) has no `is_signed_b_i` port at all.

## Parameters

None — fixed to the PE configuration, as [disp_array_b](./disp_array_b.md).

| Localparam              | Value  | Meaning                                          |
| ----------------------- | ------ | ------------------------------------------------ |
| `NUM_BLK` / `BLK_WIDTH` | 4 / 64 | Operand blocks in the 256-bit word.              |
| `NUM_PAIR` / `NUM_DP8`  | 8 / 16 | DP8 pairs and DP8s served by the column.         |
| `B_ELEM_WIDTH`          | 4      | Raw int4 element.                                |
| `B_OUT_WIDTH`           | 5      | **NEW** — resolved signed element (`4 + 1`).     |
| `B_SUM_WIDTH`           | 6      | **NEW** — pair sum (`4 + 2`), see the gate page. |
| `NUM_B_SUM`             | 4      | **NEW** — pair sums per DP8 (8 lanes / 2).       |
| `B_DP8_WIDTH`           | 40     | **CHANGED** — 8 × 5, was 8 × 4 = 32.             |
| `B_SDP8_WIDTH`          | 24     | **NEW** — 4 × 6, the pair-sum bus.               |

## Interface

| Signal                | Dir | Width   | Description                                                 |
| --------------------- | --- | ------- | ----------------------------------------------------------- |
| `clk_i`               | in  | 1       | Clock.                                                      |
| `rst_ni`              | in  | 1       | Asynchronous active-low reset.                              |
| `pe_in_b_i`           | in  | 256     | Raw B operand word (4 blocks × 64).                         |
| `sel_b_i[0:7]`        | in  | 2 each  | Per-pair 4→1 block select, from `ctrl`.                     |
| `ctr_l_i[0:7]`        | in  | 2 each  | B-gate op for the low half (pass/zero/negate/negate-carry). |
| `ctr_h_i[0:7]`        | in  | 2 each  | B-gate op for the high half.                                |
| `is_signed_b_i[0:15]` | in  | 1 each  | **NEW** — per-DP8 B signedness, from `ctrl`; consumed here. |
| `b_dp8_o[0:15]`       | out | 40 each | **CHANGED** — 8 × 5-bit exact signed lane values.           |
| `b_sum_dp8_o[0:15]`   | out | 24 each | **NEW** — 4 × 6-bit pairwise sums.                          |

Both outputs are broadcast to every PE in the column. The operand word is registered on input; the dispatch itself is combinational.

## Instantiation

```systemverilog
disp_array_b_bpl_bfp disp_array_b_bpl_bfp_i (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .pe_in_b_i    (pe_in_b),
    .sel_b_i      (sel_b),
    .ctr_l_i      (ctr_l),
    .ctr_h_i      (ctr_h),
    .is_signed_b_i(is_signed_b),
    .b_dp8_o      (b_dp8),
    .b_sum_dp8_o  (b_sum_dp8)
);
```

## Internal logic

The chain per DP8 pair is:

```
pe_in_b → reg_n → 4→1 block select (sel_b) → H/L split → gate_b_n (ctr_h/ctr_l)
                                                              → gate_b_n_bpl_bfp (is_signed_b)
                                                                    → b_dp8_o, b_sum_dp8_o
```

Everything up to and including `gate_b_n` is [disp_array_b](./disp_array_b.md) verbatim — the same input register, the same per-pair block select, the same fixed high/low split feeding the even/odd DP8 of each pair, and the same conditioning gate with its carry chained from the low half into the high half. This page covers only the added stage.

### The added per-DP8 gate

One [gate_b_n_bpl_bfp](./gate_b_n_bpl_bfp.md) per DP8 (16 instances) sits **downstream** of the conditioning gate and turns that half's eight conditioned int4 nibbles into the two output sets. It must sit after the gate, not before: the pair sums have to be sums of the values the DP8 actually multiplies — zeroed for an idle lane, negated for a complex-mode imaginary term. Summing raw nibbles would leave the multiplexer's `11` input inconsistent with its `01`/`10` inputs.

The negate carry crosses the **H/L half** boundary only, never a lane pair, so pairing stays entirely inside one DP8 and a negated operand still pairs correctly.

### Where signedness is spent

`is_signed_b_i[j]` feeds only instance `j`'s gate. Once the gate has widened each nibble to its exact signed 5-bit value, the flag has done its job — nothing downstream needs it. This is the one interface change that ripples all the way up: [pe_bpl_bfp](./pe_bpl_bfp.md) and [pe_array_bpl_bfp](./pe_array_bpl_bfp.md) both drop `is_signed_b_i`, and in [top_NxN_bpl_bfp](../architectures/top_NxN_bpl_bfp.md) `ctrl`'s `is_signed_b` fans out to the `N` dispatchers instead of the `N²` PEs.

`is_signed_a` is untouched by all of this — A stays raw int8 in [disp_array_a](./disp_array_a.md), and its signedness is still consumed inside each DP8.

## Verification

[tb_disp_array_bpl_bfp](../testbenches/tb_disp_array_bpl_bfp.md) drives all 11 modes with `ctrl`'s real control vectors and checks both outputs of every DP8 against a golden model of the whole chain — block select, H/L split, the per-int4 gate including the cross-half negate carry, the signedness-aware widening, and the four pairwise sums.

Source: [disp_array_b_bpl_bfp.sv](../../rtl/disp_array_b_bpl_bfp.sv) — Testbench: [tb_disp_array_bpl_bfp.sv](../../tb/tb_disp_array_bpl_bfp.sv) — Diagram: [disp_array_b_bpl_bfp](../../doc/diagrams/disp_array_b_bpl_bfp.excalidraw)
