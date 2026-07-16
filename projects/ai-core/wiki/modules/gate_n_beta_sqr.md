# Beta Bias Gate N (Square)

`gate_n_beta_sqr` — the fixed-bias / idle-zero variant of [gate_n_sqr](./gate_n_sqr.md), for the β generator's **low (×1) block**. For each of `SIZE` pre-centered signed nibbles it **always** subtracts `2^(WIDTH-1)` when active, or forces a real `0` when `zero_i` (idle DP8). Widens `WIDTH → WIDTH+1`.

## Purpose

In [dp_8_beta_sqr](./dp_8_beta_sqr.md) the low block compensates `b·A_low`, and A's low nibble is **structurally always unsigned**, so the removed-operand bias is a *fixed* `−8` — there is no signed pass branch. Unlike the flag-driven [gate_n_sqr](./gate_n_sqr.md), that fixed `−8` does **not** vanish on a dispatcher-zeroed idle input: it would inject `(−8)² = 64` per lane. So this gate carries its own `zero_i` to force the block to a genuine `0` on idle DP8s (the high block self-cleans via `is_signed_a = 1`). See [square_imp.md](../../doc/formulas/square/square_imp.md) §3 for the idle-leak analysis.

## Parameters

| Parameter | Default | Description                                     |
| --------- | ------- | ----------------------------------------------- |
| `WIDTH`   | `4`     | Input nibble width (int4); output is `WIDTH+1`. |
| `SIZE`    | `8`     | Number of words (all share `zero_i`).           |

## Interface

| Signal            | Dir | Width          | Description                                                 |
| ----------------- | --- | -------------- | ----------------------------------------------------------- |
| `in_i[0:SIZE-1]`  | in  | `WIDTH` each   | Pre-centered signed nibbles.                                |
| `zero_i`          | in  | 1              | `1` forces `out_o = 0` (idle); `0` subtracts `2^(WIDTH-1)`. |
| `out_o[0:SIZE-1]` | out | `WIDTH+1` each | 5-bit squarer argument.                                     |

## Internal logic

Same subtract remap as [gate_n_sqr](./gate_n_sqr.md), but unconditional (no sign-extend branch) and gated by `zero_i`:

```systemverilog
assign out_o[i] = zero_i ? '0 :
    {1'b1, ~in_i[i][WIDTH-1], in_i[i][WIDTH-2:0]};
```

Source: [gate_n_beta_sqr.sv](../../rtl/gate_n_beta_sqr.sv) — used by [dp_8_beta_sqr](./dp_8_beta_sqr.md)
