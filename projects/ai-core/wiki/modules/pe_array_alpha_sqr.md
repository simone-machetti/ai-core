# PE Array Alpha (Square)

`pe_array_alpha_sqr` — the per-row **A-only correction generator**. It is [pe_array_sqr](./pe_array_sqr.md) with the B operand removed and the 16 DP8 cores swapped to [dp_8_alpha_sqr](./dp_8_alpha_sqr.md): identical 4-level crossed CPR-4:2 tree, complex-mode block negate, widths and taps.

## Purpose

It reduces the 16 per-DP8 alpha square-sums `ALPHA_DP8` through the **same** linear tree `L(·)` as the PE, so the downstream `Result = ½(PE − α − β + C)` is exact (α, β and PE must pass through the identical reduction). One instance per grid **row**, fanned into every PE in that row. See [square_imp.md](../../doc/formulas/square/square_imp.md) §5–§7 for the amortization.

Everything below the DP8 leaves is byte-identical to [pe_array_sqr](./pe_array_sqr.md): the crossed L0 pairing (`CX0 = 4·(n/2)+n%2`, `CX1 = CX0+2`), the 6 [comp_n](./comp_n.md) block-negates on L0 nodes 0–5, the unsigned L0-hi `shift_n`, the single L0 register, and the tap slicing. α's blocks carry the **same** `neg` as the PE — a negated block resolves to `−ALPHA_DP8−2`, the deferred `+2` folding into `acc_array_sqr`'s `C`.

## Interface

Same as [pe_array_sqr](./pe_array_sqr.md), except `b_dp8_i` is **dropped** and a per-DP8 `is_signed_b_i` is **added**:

| Signal                   | Dir | Width       | Description                                         |
| ------------------------ | --- | ----------- | --------------------------------------------------- |
| `clk_i` / `rst_ni`       | in  | 1           | Clock / async active-low reset.                     |
| `a_dp8_i[0:15]`          | in  | 64 each     | Pre-centered A per DP8, from `disp_array_a_sqr`.    |
| `is_signed_b_i[0:15]`    | in  | 1 each      | **NEW** — removed-B signedness (drives the α bias). |
| `neg_i[5:0]`             | in  | 6           | Per-block negate (modes 10/11), same as PE.         |
| `sel_shift_i[2:0]`       | in  | 1 each      | Per-level shift enable.                             |
| `l0..l3_sum_o`/`carry_o` | out | 19/30/38/39 | Carry-save taps at every level.                     |

## Instantiation

```systemverilog
pe_array_alpha_sqr pe_array_alpha_sqr_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .is_signed_b_i(is_signed_b),
    .neg_i(neg), .sel_shift_i(sel_shift),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry), /* ...l1..l3... */
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry)
);
```

Widths and taps are identical to [pe_array_sqr](./pe_array_sqr.md) (node 18/26/30/38/39, tap 19/30/38/39) — the α square-sum shares the PE's per-square bound `[0,256]`, so the tree never grows differently.

Diagram: [pe_array_alpha_sqr](../../doc/diagrams/pe_array_alpha_sqr.excalidraw).

Source: [pe_array_alpha_sqr.sv](../../rtl/pe_array_alpha_sqr.sv) — core: [dp_8_alpha_sqr](./dp_8_alpha_sqr.md) — Testbench: [tb_pe_array_alpha_sqr.sv](../../tb/tb_pe_array_alpha_sqr.sv)
