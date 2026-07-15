# Gate B N (Square)

`gate_b_n_sqr` — B-operand centering gate for the square datapath. For each int4 word it flips the nibble MSB iff unsigned (centering to `[−8,7]`), or forces a real zero when the DP8 is idle.

## Purpose

The square variant's replacement for [gate_b_n](./gate_b_n.md): it keeps **pass/zero** and adds **centering**, but **drops the negate** (`GATE_NEG`/`GATE_NEG_CARRY`) and its carry chain — the complex-mode B-negate has moved into `pe_array_sqr` as a per-DP8 carry-save block-negate ([square_imp.md](../../doc/formulas/square/square_imp.md) §4). It is the B counterpart of [gate_a_n_sqr](./gate_a_n_sqr.md); centering is done here (once at the dispatcher) so the PE and β generator share it.

## Parameters

| Parameter | Default | Description                              |
| --------- | ------- | ---------------------------------------- |
| `WIDTH`   | 4       | Word width (int4 nibble).                |
| `SIZE`    | 8       | Words per gate (a DP8 half = 8 nibbles). |

## Interface

| Signal        | Dir | Width  | Description                               |
| ------------- | --- | ------ | ----------------------------------------- |
| `in_i[0:7]`   | in  | 4 each | Raw int4 nibbles.                         |
| `is_signed_i` | in  | 1      | Operand signedness (drives the MSB flip). |
| `zero_i`      | in  | 1      | Idle: force the whole word to `0`.        |
| `out_o[0:7]`  | out | 4 each | Centered (or zeroed) int4 nibbles.        |

## Instantiation

```systemverilog
gate_b_n_sqr #(.WIDTH(4), .SIZE(8)) gate_b_n_sqr_h_i (
    .in_i(bhi_nib), .is_signed_i(is_signed_b[2*p]), .zero_i(zero_i[2*p]), .out_o(bhi_gated)
);
```

## Internal logic

Purely combinational — one continuous assign per word:

```systemverilog
assign out_o[i] = zero_i ? '0 :
    {in_i[i][WIDTH-1] ^ ~is_signed_i, in_i[i][WIDTH-2:0]};
```

Flip the MSB iff unsigned (`u ↦ u−8`), pass the low bits, force a real `0` when idle. There are **no** `carry_i`/`carry_o` ports — with the negate gone there is nothing to chain across the nibble boundary that [gate_b_n](./gate_b_n.md) needed for an int8 two's-complement negate.

Source: [gate_b_n_sqr.sv](../../rtl/gate_b_n_sqr.sv) — Used by: [disp_array_b_sqr](./disp_array_b_sqr.md)
