# PE Array Beta (Square)

`pe_array_beta_sqr` — the per-column **B-only correction generator**. It is [pe_array_sqr](./pe_array_sqr.md) with the A operand removed and the 16 DP8 cores swapped to [dp_8_beta_sqr](./dp_8_beta_sqr.md): identical 4-level crossed CPR-4:2 tree, complex-mode block negate, widths and taps.

## Purpose

It reduces the 16 per-DP8 beta square-sums `BETA_DP8` through the **same** linear tree `L(·)` as the PE, so the downstream `Result = ½(PE − α − β + C)` is exact. One instance per grid **column**, fanned into every PE in that column. See [square_imp.md](../../doc/formulas/square/square_imp.md) §5–§7.

Everything below the DP8 leaves is byte-identical to [pe_array_sqr](./pe_array_sqr.md) (crossed L0 pairing, 6 [comp_n](./comp_n.md) block-negates on L0 nodes 0–5, unsigned L0-hi `shift_n`, single L0 register, tap slicing). β's blocks carry the **same** `neg` as the PE — a negated block resolves to `−BETA_DP8−2`. Idle DP8s are forced to a real zero via `zero_i` (the β low block's fixed `−8` would otherwise leak).

## Output — emits `−β`

The output taps are **one's-complemented** (`~l*_sum_o` / `~l*_carry_o`, all four levels), so the module emits **`−β`**: each carry-save tap pair resolves to `−β_tap − 2`. This lets the accumulator just **add** the β term instead of subtracting it — the whole square accumulator is then a pure carry-save sum `PE + (−α) + (−β) + C`, with **no subtractor**. The complement is done **once here** (shared by the column's 8 PEs) rather than in each of the 64 accumulators. The deferred `−2` per operand (one for α, one for β) is the `+4` folded into [const_sqr](./const_sqr.md)'s `C`. The 6 block-`comp_n` are unchanged — they still give β the complex σ sign inside the tree; the output `~` then negates the whole (correctly-signed) result.

## Interface

Same as [pe_array_sqr](./pe_array_sqr.md), except `a_dp8_i` is **dropped** and per-DP8 `is_signed_a_i` + `zero_i` are **added**:

| Signal                   | Dir | Width       | Description                                                         |
| ------------------------ | --- | ----------- | ------------------------------------------------------------------- |
| `clk_i` / `rst_ni`       | in  | 1           | Clock / async active-low reset.                                     |
| `b_dp8_i[0:15]`          | in  | 32 each     | Pre-centered B per DP8, from `disp_array_b_sqr`.                    |
| `is_signed_a_i[0:15]`    | in  | 1 each      | **NEW** — removed A-high signedness (drives the β high-block bias). |
| `zero_i[0:15]`           | in  | 1 each      | **NEW** — idle-zero for the β low block.                            |
| `neg_i[5:0]`             | in  | 6           | Per-block negate (modes 10/11), same as PE.                         |
| `sel_shift_i[2:0]`       | in  | 1 each      | Per-level shift enable.                                             |
| `l0..l3_sum_o`/`carry_o` | out | 19/30/38/39 | Carry-save `−β` taps (one's-complemented) at every level.           |

## Instantiation

```systemverilog
pe_array_beta_sqr pe_array_beta_sqr_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .b_dp8_i(b_dp8), .is_signed_a_i(is_signed_a), .zero_i(zero_dp8),
    .neg_i(neg), .sel_shift_i(sel_shift),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry), /* ...l1..l3... */
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry)
);
```

Widths and taps are identical to [pe_array_sqr](./pe_array_sqr.md) (node 18/26/30/38/39, tap 19/30/38/39).

Diagram: [pe_array_beta_sqr](../../doc/diagrams/pe_array_beta_sqr.excalidraw).

Source: [pe_array_beta_sqr.sv](../../rtl/pe_array_beta_sqr.sv) — core: [dp_8_beta_sqr](./dp_8_beta_sqr.md) — Testbench: [tb_pe_array_beta_sqr.sv](../../tb/tb_pe_array_beta_sqr.sv)
