# PE Grid (Bit-Plane-B BFP)

`top_NxN_bpl_b_bfp` — the **bit-plane-B BFP** N × N grid, the [top_NxN_bfp](./top_NxN_bfp.md) analogue built on the bit-plane **row** dispatch and PE ([disp_array_a_bpl_b_bfp](../modules/disp_array_a_bpl_b_bfp.md), [pe_bpl_b_bfp](../modules/pe_bpl_b_bfp.md)). It tiles N² cores, sharing operand A (mantissa + exponent) along each row and B along each column, so PE[r][c] evaluates `A[r] · B[c]` in block floating point — with the same values as `top_NxN_bfp`.

**The best grid in the project on both axes: −13.7 % area and −14.5 % power at 8×8 against baseline-BFP, with a crossover at N = 1.**

## Purpose

[top_NxN_bpl_a_bfp](./top_NxN_bpl_a_bfp.md) proved the bit-plane lever works but left most of it on the table. This grid is the same idea with the operand roles exchanged, following one rule:

> **Index with the narrow operand, tabulate the wide one.**

B is 4 bits and A is 8, so decomposing over B's planes halves the partial-product count — 4 planes instead of 8. The tabulated entry `a₂ⱼ + a₂ⱼ₊₁` is a function of **A alone**, so it hoists into each **row's** dispatcher instead of each column's:

| term                              | cost                   | scales as |
| --------------------------------- | ---------------------- | --------- |
| pair-sum adders                   | `N` rows × 8 pairs × 4 | **O(N)**  |
| bit-plane selection + compression | `N²` PEs               | **O(N²)** |

The overhead is `+43 %` on one dispatcher (`397.50` vs `277.73` µm²) against a per-tile saving of `968.30` µm² of PE, so — as in the A build — **the crossover is at N = 1**: smaller and lower-power than baseline-BFP at every size, including 2×2.

Measured against [top_NxN_bfp](./top_NxN_bfp.md):

| metric | 8×8         | 16×16       | asymptote | crossover |
| ------ | ----------- | ----------- | --------- | --------- |
| area   | **−13.7 %** | **−13.9 %** | −14.2 %   | N = 1.00  |
| power  | **−14.5 %** | **−15.0 %** | −15.6 %   | N = 1.00  |

Against the A build that is **4× the area saving and 20× the power saving**. See [Synthesis Area](../experiments/syn_area.md), [Synthesis Power](../experiments/syn_pwr.md) and [Grid Scaling](../experiments/syn_scaling.md).

## Parameters

| Parameter | Default | Description                                                                    |
| --------- | ------- | ------------------------------------------------------------------------------ |
| `N`       | 2       | Grid side — the array is `N × N` PEs. Chip target 8×8; a single PE is `N = 1`. |

## Interface

**Identical, port for port, to [top_NxN_bfp](./top_NxN_bfp.md)** — the bit-plane operand contract is entirely internal:

| Signal                                    | Dir | Description                                                                    |
| ----------------------------------------- | --- | ------------------------------------------------------------------------------ |
| `clk_i` / `rst_ni`                        | in  | Clock, asynchronous active-low reset.                                          |
| `in_a_i[0:N-1]` / `in_b_i[0:N-1]`         | in  | 256-bit mantissa operand per row / per column.                                 |
| `in_exp_a_i[0:N-1]` / `in_exp_b_i[0:N-1]` | in  | Per-row A format exponents (4 × 6-bit) / per-column B (4 × 2 × 6-bit).         |
| `mode_i`                                  | in  | Operating mode (4-bit), decoded once by the shared `ctrl`.                     |
| `sel_acc_i`                               | in  | Seed vs feedback for every PE's accumulator.                                   |
| `acc_i` / `acc_exp_i`                     | in  | Per-PE, per-lane accumulator seed mantissa and scale.                          |
| `en_row_i[0:N-1]` / `en_col_i[0:N-1]`     | in  | Row / column enables — scale the active region to any `rows × cols` rectangle. |
| `out_q_o` / `out_exp_o`                   | out | Per-PE, per-lane raw un-normalized result mantissa and scale.                  |

## Instantiation

```systemverilog
top_NxN_bpl_b_bfp #(.N(8)) top_NxN_bpl_b_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .in_a_i(in_a), .in_b_i(in_b),
    .in_exp_a_i(in_exp_a), .in_exp_b_i(in_exp_b),
    .mode_i(mode), .sel_acc_i(sel_acc),
    .acc_i(acc), .acc_exp_i(acc_exp),
    .en_row_i(en_row), .en_col_i(en_col),
    .out_q_o(out_q), .out_exp_o(out_exp)
);
```

## Composition

Against [top_NxN_bfp](./top_NxN_bfp.md) exactly **two instances change** — and they are the mirror image of the A build's two:

| per    | `top_NxN_bfp`                                 | `top_NxN_bpl_a_bfp`                      | `top_NxN_bpl_b_bfp`                      |
| ------ | --------------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| grid   | `ctrl`, `sel_acc` pipeline                    | same                                     | same                                     |
| row    | `disp_array_a`, `disp_array_exp_a_bfp`, `icg` | same                                     | **`disp_array_a_bpl_b_bfp`**, same, same |
| column | `disp_array_b`, `disp_array_exp_b_bfp`, `icg` | **`disp_array_b_bpl_a_bfp`**, same, same | same (the **plain** `disp_array_b`)      |
| tile   | `pe_bfp`, `icg`                               | **`pe_bpl_a_bfp`**, same                 | **`pe_bpl_b_bfp`**, same                 |

Each row dispatcher now emits two buses — the 8 × 9-bit resolved A values and the 4 × 10-bit pair sums — both broadcast along the row. The column route reverts to the plain [disp_array_b](../modules/disp_array_b.md) and B reaches the PEs as raw int4. Clock-gating structure, pipeline depth and the `en_row`/`en_col` rectangle scaling are untouched.

### Where `is_signed_a` goes

Because [disp_array_a_bpl_b_bfp](../modules/disp_array_a_bpl_b_bfp.md) resolves A to signed values, `ctrl`'s `is_signed_a` feeds the **N dispatchers** and never reaches the N² PEs. This is the only control-fanout change in the grid — the A build does the same with `is_signed_b`.

### Masking `is_signed_b` for idle DP8s

The one piece of logic unique to this top level, and the mirror of the A build's idle mask. For the DP8s a mode leaves idle, `is_signed_b` is cleared, taken straight from `ctrl`'s zero gate codes:

```systemverilog
for (p = 0; p < NUM_PAIR; p++) begin : gen_idle_mask
    assign is_signed_b_g[2*p+0] = is_signed_b[2*p+0] & (ctr_h[p] != GATE_ZERO);
    assign is_signed_b_g[2*p+1] = is_signed_b[2*p+1] & (ctr_l[p] != GATE_ZERO);
end
```

Why it is needed: an idle DP8 multiplies a zero B, so its **value** does not depend on the flag — but its *encoding* does. With `is_signed_b` set, [dp_8_bpl_b_bfp](../modules/dp_8_bpl_b_bfp.md)'s weight-2³ correction one's-complements a column and injects a `+2⁴` constant, and the two cancel to a **non-canonical zero**: a carry-save pair with `s + c = 0` but `s ≠ 0`. The BFP aligner downstream right-shifts such a pair, and the cancellation is lost. Clearing the flag keeps an idle DP8's result an exact, canonical zero.

Note the asymmetry with the A build: there the masked flag belongs to the operand that is *not* zeroed, here it belongs to the operand that *is*. The mask is still required, for exactly the encoding reason above.

Both sides of an idle DP8's exponent are already gated to zero by the exponent dispatchers, as in `top_NxN_bfp`, so its scale never wins a max.

## Verification

[tb_top_NxN_bpl_b_bfp](../testbenches/tb_top_NxN_bpl_b_bfp.md) drives the grid at **full pipeline throughput** with distinct A per row and B per column, over three streaming patterns (single-shot, accumulation, rectangle scaling) × 11 modes × two exponent experiments. **66/66, N = 2, 0 mismatches**, `-Wall` clean. [tb_top_NxN_bpl_b_bfp_pwr](../../tb/tb_top_NxN_bpl_b_bfp_pwr.sv) supplies the VCD stimulus for the power experiments.

Independently, [tb_top_NxN_global](../testbenches/tb_top_NxN_global.md) instantiates this grid **next to** [top_NxN_bfp](./top_NxN_bfp.md) in one bench and asserts `golden == baseline-BFP == bit-plane-B` at max throughput — a direct RTL-vs-RTL equivalence rather than two independent comparisons against a model.

Source: [top_NxN_bpl_b_bfp.sv](../../rtl/top_NxN_bpl_b_bfp.sv) — Testbench: [tb_top_NxN_bpl_b_bfp.sv](../../tb/tb_top_NxN_bpl_b_bfp.sv) — Diagram: [top_NxN_bpl_b_bfp](../../doc/diagrams/top_NxN_bpl_b_bfp.excalidraw) — Derivation: [basics.tex](../../doc/formulas/bit-plane-bfp/basics.tex)
