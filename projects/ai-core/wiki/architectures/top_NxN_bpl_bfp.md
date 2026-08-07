# PE Grid (Bit-Plane BFP)

`top_NxN_bpl_bfp` — the **bit-plane BFP** N × N grid, the [top_NxN_bfp](./top_NxN_bfp.md) analogue built on the bit-plane column dispatch and PE ([disp_array_b_bpl_bfp](../modules/disp_array_b_bpl_bfp.md), [pe_bpl_bfp](../modules/pe_bpl_bfp.md)). It tiles N² cores, sharing operand A (mantissa + exponent) along each row and B along each column, so PE[r][c] evaluates `A[r] · B[c]` in block floating point — with the same values as `top_NxN_bfp`.

## Purpose

The grid is where the bit-plane idea pays. Inside a PE, [dp_8_bpl_bfp](../modules/dp_8_bpl_bfp.md) replaces Booth recoding of B with a 4:1 multiplexer per lane pair per bit plane of A. The fourth mux input — the pairwise sum `b₂ⱼ + b₂ⱼ₊₁` — is a function of **B alone**, so it is hoisted into each column's dispatcher and broadcast:

| term | cost | scales as |
| --- | --- | --- |
| pair-sum adders | `N` × 16 DP8s × 4 sums | **O(N)** |
| bit-plane selection + compression | `N²` PEs | **O(N²)** |

That is the same lever the square variant pulls with its α/β generators, but a much cheaper one: the overhead is `+32 %` on one dispatcher (`616.22` vs `466.33` µm²) rather than two extra per-row/per-column arrays, so **the crossover is at N = 1** — the bit-plane grid is smaller than baseline-BFP at every size, including 2×2.

Measured against [top_NxN_bfp](./top_NxN_bfp.md): area **−3.3 %** at 8×8 and **−3.5 %** at 16×16 (asymptote −3.7 %); power **−0.30 %** and **−0.75 %** (crossover N ≈ 5.9, asymptote −1.2 %). See [Synthesis Area](../experiments/syn_area.md), [Synthesis Power](../experiments/syn_pwr.md) and [Grid Scaling](../experiments/syn_scaling.md).

## Parameters

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| `N`       | 2       | Grid side — the array is `N × N` PEs. Chip target 8×8; a single PE is `N = 1`. |

## Interface

**Identical, port for port, to [top_NxN_bfp](./top_NxN_bfp.md)** — the bit-plane operand contract is entirely internal:

| Signal | Dir | Description |
| ------ | --- | ----------- |
| `clk_i` / `rst_ni` | in | Clock, asynchronous active-low reset. |
| `in_a_i[0:N-1]` / `in_b_i[0:N-1]` | in | 256-bit mantissa operand per row / per column. |
| `in_exp_a_i[0:N-1]` / `in_exp_b_i[0:N-1]` | in | Per-row A format exponents (4 × 6-bit) / per-column B (4 × 2 × 6-bit). |
| `mode_i` | in | Operating mode (4-bit), decoded once by the shared `ctrl`. |
| `sel_acc_i` | in | Seed vs feedback for every PE's accumulator. |
| `acc_i` / `acc_exp_i` | in | Per-PE, per-lane accumulator seed mantissa and scale. |
| `en_row_i[0:N-1]` / `en_col_i[0:N-1]` | in | Row / column enables — scale the active region to any `rows × cols` rectangle. |
| `out_q_o` / `out_exp_o` | out | Per-PE, per-lane raw un-normalized result mantissa and scale. |

## Instantiation

```systemverilog
top_NxN_bpl_bfp #(.N(8)) top_NxN_bpl_bfp_i (
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

Against [top_NxN_bfp](./top_NxN_bfp.md) exactly **two instances change**:

| per | `top_NxN_bfp` | `top_NxN_bpl_bfp` |
| --- | --- | --- |
| grid | `ctrl`, `sel_acc` pipeline | same |
| row | `disp_array_a`, `disp_array_exp_a_bfp`, `icg` | same |
| column | `disp_array_b`, `disp_array_exp_b_bfp`, `icg` | **`disp_array_b_bpl_bfp`**, same, same |
| tile | `pe_bfp`, `icg` | **`pe_bpl_bfp`**, same |

Each column dispatcher now emits two buses — the 8 × 5-bit resolved B values and the 4 × 6-bit pair sums — both broadcast down the column. Clock-gating structure, pipeline depth and the `en_row`/`en_col` rectangle scaling are untouched.

### Where `is_signed_b` goes

Because [disp_array_b_bpl_bfp](../modules/disp_array_b_bpl_bfp.md) resolves B to signed values, `ctrl`'s `is_signed_b` feeds the **N dispatchers** and never reaches the N² PEs. This is the only control-fanout change in the grid.

### Masking `is_signed_a` for idle DP8s

The one piece of logic unique to this top level. For the DP8s a mode leaves idle, `is_signed_a` is cleared, taken straight from `ctrl`'s zero gate codes:

```systemverilog
for (p = 0; p < NUM_PAIR; p++) begin : gen_idle_mask
    assign is_signed_a_g[2*p+0] = is_signed_a[2*p+0] & (ctr_h[p] != GATE_ZERO);
    assign is_signed_a_g[2*p+1] = is_signed_a[2*p+1] & (ctr_l[p] != GATE_ZERO);
end
```

Why it is needed: an idle DP8 multiplies a zero B, so its **value** does not depend on the flag — but its *encoding* does. With `is_signed_a` set, [dp_8_bpl_bfp](../modules/dp_8_bpl_bfp.md)'s weight-2⁷ correction one's-complements a column and injects a `+2⁸` constant, and the two cancel to a **non-canonical zero**: a carry-save pair with `s + c = 0` but `s ≠ 0`. The BFP aligner downstream right-shifts such a pair, and the cancellation is lost. Clearing the flag keeps an idle DP8's result an exact, canonical zero.

Both sides of an idle DP8's exponent are already gated to zero by the exponent dispatchers, as in `top_NxN_bfp`, so its scale never wins a max.

## Verification

[tb_top_NxN_bpl_bfp](../testbenches/tb_top_NxN_bpl_bfp.md) drives the grid at **full pipeline throughput** with distinct A per row and B per column, over three streaming patterns (single-shot, accumulation, rectangle scaling) × 11 modes × two exponent experiments: equal-exponent as a bit-exact black-box matmul, distinct-exponent against an independent exponent model and mantissa window. **66/66, N = 2, 0 mismatches**, `-Wall` clean. [tb_top_NxN_bpl_bfp_pwr](../../tb/tb_top_NxN_bpl_bfp_pwr.sv) supplies the VCD stimulus for the power experiments.

Source: [top_NxN_bpl_bfp.sv](../../rtl/top_NxN_bpl_bfp.sv) — Testbench: [tb_top_NxN_bpl_bfp.sv](../../tb/tb_top_NxN_bpl_bfp.sv) — Diagram: [top_NxN_bpl_bfp](../../doc/diagrams/top_NxN_bpl_bfp.excalidraw)
