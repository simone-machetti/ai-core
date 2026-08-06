# Dot Product 8 Beta (Square)

`dp_8_beta_sqr` — the B-only generator DP8 for the square datapath. It is [dp_8_sqr](./dp_8_sqr.md) with the **A operand removed**: the single pre-centered `b` nibble feeds **two** blocks, each squared, so β compensates the b²-term of *both* products (`AH·b` and `AL·b`) each `b` participates in. It produces the per-DP8 **beta** square-sum in 18-bit carry-save form.

## Purpose

β is the B-only correction term of `Result = ½(PE − α − β + C)`. Per DP8 it is

```
BETA_DP8 = 2^4 · Σ_k (B_k − 8·au)²  +  Σ_k (B_k − 8)²             au = ~is_signed_a
```

The high (`<<4`) block subtracts the removed A-**high**'s `−8` via a [gate_n_sqr](./gate_n_sqr.md) driven by `is_signed_a_i`; the low block subtracts a **fixed** `−8` via a [gate_n_beta_sqr](./gate_n_beta_sqr.md) (A-low is structurally always unsigned) or zeros on idle. The asymmetry (one flag-driven bias, one fixed) is why β keeps both AH and AL blocks even though A's data is gone. Downstream (16 [s_5_bit_sqr](./s_5_bit_sqr.md), two unsigned [cpr_w_n](./cpr_w_n.md) 8:2, high block `<<4`, one unsigned `cpr_w_n` 4:2 → 18-bit) is identical to [dp_8_sqr](./dp_8_sqr.md).

Unlike α, the low block's `−8` is fixed and would inject `(−8)² = 64` per lane on a dispatcher-zeroed idle DP8, so `zero_i` forces that block to a real `0` (the high block self-cleans via `is_signed_a = 1`).

## Interface

| Signal              | Dir | Width   | Description                                                               |
| ------------------- | --- | ------- | ------------------------------------------------------------------------- |
| `b_i[0:7]`          | in  | 4 each  | Pre-centered int4 B lanes (fed to both blocks).                           |
| `is_signed_a_i`     | in  | 1       | Removed A-high signedness; `0` (unsigned) → subtract 8 on the high block. |
| `zero_i`            | in  | 1       | Idle: force the low block (and thus the DP8) to `0`.                      |
| `sum_o` / `carry_o` | out | 18 each | Carry-save `BETA_DP8` (16-bit value + 2 guard, unsigned).                 |

## Internal logic

```systemverilog
// high (<< 4) block: flag-selected -8 by the removed A-high signedness
gate_n_sqr #(.WIDTH(IN_WIDTH_B), .SIZE(LANES)) gate_n_sqr_ah_i (
    .in_i(b_i), .is_signed_i(is_signed_a_i), .out_o(arg_ah)
);
// low block: fixed -8 (A-low always unsigned), zero on idle
gate_n_beta_sqr #(.WIDTH(IN_WIDTH_B), .SIZE(LANES)) gate_n_beta_sqr_al_i (
    .in_i(b_i), .zero_i(zero_i), .out_o(arg_al)
);
// 16 s_5_bit_sqr, two cpr_w_n 8:2 (unsigned), high block << 4, cpr_w_n 4:2 -> 18-bit
```

The high block is the shifted (`<<4`) one, matching the `B(AH)` / `B(AL)` copies in the diagram. Widths are identical to [dp_8_sqr](./dp_8_sqr.md). Combinational.

Diagram: [dp_8_beta_sqr](../../doc/diagrams/dp_8_beta_sqr.excalidraw).

Source: [dp_8_beta_sqr.sv](../../rtl/dp_8_beta_sqr.sv) — instantiated by [pe_array_beta_sqr](./pe_array_beta_sqr.md)
