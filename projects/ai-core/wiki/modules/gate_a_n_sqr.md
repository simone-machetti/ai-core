# Gate A N (Square)

`gate_a_n_sqr` — A-operand centering gate for the square datapath. For each int8 word it produces the two **centered** signed nibbles the square PE expects, or a real zero when the DP8 is idle.

## Purpose

The square datapath ([dp_8_sqr](./dp_8_sqr.md)) works on nibbles pre-centered to the signed range `[−8,7]`, so the `−8` bias is applied once at the dispatcher and shared by the PE and the α/β generators. `gate_a_n_sqr` does that for A: within an int8 `{AH, AL}` it flips the **low** nibble MSB unconditionally (AL is never an operand MSN → always unsigned) and the **high** nibble MSB iff `~is_signed_i`. `zero_i` overrides to a real `0` so an idle DP8 squares `(0+0)² = 0`. It is the A counterpart of [gate_b_n_sqr](./gate_b_n_sqr.md); the baseline A path had no gate, since A was never conditioned. See [square_imp.md](../../doc/formulas/square/square_imp.md) §5.

## Parameters

| Parameter | Default | Description                       |
| --------- | ------- | --------------------------------- |
| `WIDTH`   | 8       | Word width (int8).                |
| `SIZE`    | 8       | Words per gate (a DP8's 8 lanes). |
| `NIB`     | 4       | Nibble width (`localparam`).      |

## Interface

| Signal        | Dir | Width  | Description                                     |
| ------------- | --- | ------ | ----------------------------------------------- |
| `in_i[0:7]`   | in  | 8 each | Raw int8 lanes.                                 |
| `is_signed_i` | in  | 1      | Operand signedness (drives the AH-nibble flip). |
| `zero_i`      | in  | 1      | Idle: force the whole word to `0`.              |
| `out_o[0:7]`  | out | 8 each | Centered (or zeroed) int8 lanes.                |

## Instantiation

```systemverilog
gate_a_n_sqr #(.WIDTH(8), .SIZE(8)) gate_a_n_sqr_i (
    .in_i(a_lane), .is_signed_i(is_signed_a[d]), .zero_i(zero_i[d]), .out_o(o_lane)
);
```

## Internal logic

Purely combinational — one continuous assign per word:

```systemverilog
assign out_o[i] = zero_i ? '0 : {
    in_i[i][WIDTH-1] ^ ~is_signed_i,  // high-nibble MSB: flip iff unsigned
    in_i[i][WIDTH-2:NIB],             // high-nibble lower bits
    ~in_i[i][NIB-1],                  // low-nibble MSB: always flipped
    in_i[i][NIB-2:0]                  // low-nibble lower bits
};
```

Flipping a nibble's MSB maps an unsigned `[0,15]` value to its signed centered value (`u ↦ u−8`); leaving it maps a signed nibble unchanged. AL is always unsigned so its MSB always flips; AH follows `is_signed_i`. When `zero_i` is set the word is a **real** hardware zero — necessary because a centered `0` would otherwise be `−8` (and `(a−8)² ≠ 0`), so idle DP8s must be zeroed, not just centered ([square_imp.md](../../doc/formulas/square/square_imp.md) §3).

Source: [gate_a_n_sqr.sv](../../rtl/gate_a_n_sqr.sv) — Used by: [disp_array_a_sqr](./disp_array_a_sqr.md)
