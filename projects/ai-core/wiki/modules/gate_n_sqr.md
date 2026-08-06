# Bias Gate N (Square)

`gate_n_sqr` — the flag-selected bias gate for the square α/β generators. For each of `SIZE` pre-centered signed nibbles it produces the 5-bit squarer argument: **sign-extend** the input (`is_signed_i = 1`) or **subtract `2^(WIDTH-1)`** (`is_signed_i = 0`), widening `WIDTH → WIDTH+1`.

## Purpose

The α/β generators reuse the dispatcher-centered operand (already biased to `[−8,7]`) and must inject the **removed** operand's centering `−8` — the second `−8` that completes the `−16` (both-unsigned) case. This gate is that injection: it subtracts `8` when the removed operand is **unsigned**, else passes the value through (sign-extended). It never builds `−16` itself — the dispatcher already applied the first `−8`, so the gate only ever adds one more, keeping the argument in `[−16,7]`.

Used by [dp_8_alpha_sqr](./dp_8_alpha_sqr.md) (both AH and AL blocks, `is_signed_i = is_signed_b`) and by [dp_8_beta_sqr](./dp_8_beta_sqr.md)'s high (`<<4`) block (`is_signed_i = is_signed_a`). It is the invert-of-behaviour sibling of [gate_n_beta_sqr](./gate_n_beta_sqr.md) (which subtracts unconditionally and idle-zeros).

## Parameters

| Parameter | Default | Description                                     |
| --------- | ------- | ----------------------------------------------- |
| `WIDTH`   | `4`     | Input nibble width (int4); output is `WIDTH+1`. |
| `SIZE`    | `8`     | Number of words (all share `is_signed_i`).      |

## Interface

| Signal            | Dir | Width          | Description                                                |
| ----------------- | --- | -------------- | ---------------------------------------------------------- |
| `in_i[0:SIZE-1]`  | in  | `WIDTH` each   | Pre-centered signed nibbles.                               |
| `is_signed_i`     | in  | 1              | `1` = sign-extend (no bias); `0` = subtract `2^(WIDTH-1)`. |
| `out_o[0:SIZE-1]` | out | `WIDTH+1` each | 5-bit squarer argument.                                    |

## Internal logic

The subtract is the two-gate top-bit remap (set bit `WIDTH`, complement bit `WIDTH-1`, pass the rest = `in − 2^(WIDTH-1)`); the pass is a 1-bit sign-extension:

```systemverilog
assign out_o[i] = is_signed_i ?
    {in_i[i][WIDTH-1], in_i[i]} :
    {1'b1, ~in_i[i][WIDTH-1], in_i[i][WIDTH-2:0]};
```

On idle DP8s `ctrl` forces `is_signed_i = 1`, so a dispatcher-zeroed input sign-extends to a real `0` — no zero port is needed here (unlike [gate_n_beta_sqr](./gate_n_beta_sqr.md)).

Source: [gate_n_sqr.sv](../../rtl/gate_n_sqr.sv) — used by [dp_8_alpha_sqr](./dp_8_alpha_sqr.md), [dp_8_beta_sqr](./dp_8_beta_sqr.md)
