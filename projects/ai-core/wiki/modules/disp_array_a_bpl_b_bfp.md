# Dispatch Array A (Bit-Plane-B BFP)

`disp_array_a_bpl_b_bfp` — the [disp_array_a](./disp_array_a.md) variant that also produces the operands [dp_8_bpl_b_bfp](./dp_8_bpl_b_bfp.md) needs. Routing is unchanged: one 4→1 block select per pair, the selected block feeding both DP8s of the pair, all shared by a whole grid row. What is added is one [gate_n_bpl_bfp](./gate_n_bpl_bfp.md) per pair, turning the selected block's eight int8 lanes into exact signed values **and** their pairwise sums.

This is the mirror of [disp_array_b_bpl_a_bfp](./disp_array_b_bpl_a_bfp.md): there the tabulated operand is B and the gate lives in the per-**column** dispatch; here it is A and the gate lives in the per-**row** dispatch.

## Purpose

The bit-plane DP8 selects among `{0, a₂ⱼ, a₂ⱼ₊₁, a₂ⱼ + a₂ⱼ₊₁}`. Only the last entry costs anything, and it is a function of **A alone** — so it does not belong inside a PE:

| term                              | cost                   | scales as |
| --------------------------------- | ---------------------- | --------- |
| pair-sum adders                   | `N` rows × 8 pairs × 4 | **O(N)**  |
| bit-plane selection + compression | `N²` PEs               | **O(N²)** |

The dispatcher grows `277.73 → 397.50` µm² (**+43 %**) and each tile falls `5984.76 → 5016.45` µm² of PE. At any grid size that trade is already won — see [Grid Scaling](../experiments/syn_scaling.md).

## Parameters

None — fixed to the grid's dispatch configuration.

| Localparam                     | Value   | Meaning                                 |
| ------------------------------ | ------- | --------------------------------------- |
| `NUM_BLK` / `BLK_WIDTH`        | 4 / 64  | A operand blocks in the 256-bit word.   |
| `NUM_PAIR` / `NUM_DP8`         | 8 / 16  | Lane pairs; DP8s fed (two per pair).    |
| `A_ELEM_WIDTH` / `NUM_A_ELEM`  | 8 / 8   | Raw int8 lanes per block.               |
| `A_OUT_WIDTH`                  | 9       | Exact signed lane value (`WIDTH+1`).    |
| `A_SUM_WIDTH` / `NUM_A_SUM`    | 10 / 4  | Pairwise sum (`WIDTH+2`); four per DP8. |
| `A_DP8_WIDTH` / `A_SDP8_WIDTH` | 72 / 40 | Packed per-DP8 output buses.            |

## Interface

| Signal                | Dir | Width | Description                                            |
| --------------------- | --- | ----- | ------------------------------------------------------ |
| `clk_i` / `rst_ni`    | in  | 1     | Clock, asynchronous active-low reset.                  |
| `pe_in_a_i`           | in  | 256   | The row's A operand word (4 blocks × 64).              |
| `sel_a_i[0:7]`        | in  | 2     | Per-pair 4→1 block select, from `ctrl`.                |
| `is_signed_a_i[0:15]` | in  | 1     | Per-DP8 A signedness, from `ctrl` — **consumed here**. |
| `a_dp8_o[0:15]`       | out | 72    | Eight lanes widened to 9-bit exact signed values.      |
| `a_sum_dp8_o[0:15]`   | out | 40    | **NEW** — the four pairwise sums at 10 bits.           |

The 256-bit operand is registered on input; the dispatch is combinational.

## Instantiation

```systemverilog
disp_array_a_bpl_b_bfp disp_array_a_bpl_b_bfp_i (
    .clk_i        (clk_a),
    .rst_ni       (rst_ni),
    .pe_in_a_i    (in_a_i[r]),
    .sel_a_i      (sel_a),
    .is_signed_a_i(is_signed_a),
    .a_dp8_o      (a_dp8_row[r]),
    .a_sum_dp8_o  (a_sum_dp8_row[r])
);
```

## Internal logic

### One gate per pair, not per DP8

The single structural difference from [disp_array_b_bpl_a_bfp](./disp_array_b_bpl_a_bfp.md), which instantiates **16** gates — one per DP8. Here there are **8**:

```systemverilog
gate_n_bpl_bfp #(.WIDTH(A_ELEM_WIDTH), .SIZE(NUM_A_ELEM)) gate_n_bpl_bfp_i (
    .in_i(a_elem), .is_signed_i(is_signed_a_i[2*p]), .out_o(a_res), .sum_o(a_sum)
);
```

Both DP8s of a pair receive the same A block, and `ctrl`'s `is_signed_a` is uniform within a pair in every mode, so the two DP8s would resolve to identical values and identical sums. The gate is therefore driven by `is_signed_a_i[2*p]` and its outputs are **broadcast to both entries** — halving the adder count without changing a single dispatched value.

This is *gating per pair, routing per DP8*: the outputs still fan out as 16 independent per-DP8 buses, so nothing downstream can tell the difference.

### Why the gate sits directly after the block select

In the A build the gate must sit *after* the B conditioning gate, because the sums have to be of the values the DP8 actually multiplies (zeroed for an idle lane, negated for a complex-mode imaginary term). The A path has no such conditioning stage — **a lane is idled by zeroing its B**, not its A — so here the gate follows the block select directly, with nothing between.

The consequence for the grid is that idling is invisible on this side: an idle DP8 still receives live A values and live pair sums, and produces zero because its B is zero. See [top_NxN_bpl_b_bfp](../architectures/top_NxN_bpl_b_bfp.md) for the one place that is not quite enough.

### Where `is_signed_a` stops

Because the values leave already resolved, per-DP8 signedness is consumed here and **never reaches the PEs** — which is why [dp_8_bpl_b_bfp](./dp_8_bpl_b_bfp.md) has no `is_signed_a_i` port. It is the exact counterpart of `is_signed_b` in the A build.

## Verification

[tb_disp_array_bpl_b_bfp](../testbenches/tb_disp_array_bpl_b_bfp.md) drives this dispatcher and [disp_array_b](./disp_array_b.md) together against a golden model for all 11 modes, with the real per-mode control vectors from `ctrl`'s lookup tables. **11/11, 0 mismatches.**

Source: [disp_array_a_bpl_b_bfp.sv](../../rtl/disp_array_a_bpl_b_bfp.sv) — Testbench: [tb_disp_array_bpl_b_bfp.sv](../../tb/tb_disp_array_bpl_b_bfp.sv) — Diagram: [disp_array_a_bpl_b_bfp](../../doc/diagrams/disp_array_a_bpl_b_bfp.excalidraw)
