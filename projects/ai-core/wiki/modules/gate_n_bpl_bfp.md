# Gate N (Bit-Plane BFP)

`gate_n_bpl_bfp` — Parameterized bit-plane operand gate: takes `SIZE` `WIDTH`-bit words under one shared runtime signedness flag and emits **both** operand sets a bit-plane dot product needs — each word as its exact signed value at `WIDTH+1` bits, and the `SIZE/2` pairwise sums at `WIDTH+2` bits.

## Purpose

The bit-plane [dp_8_bpl_a_bfp](./dp_8_bpl_a_bfp.md) decomposes `Σ aₖ·bₖ` over the **bit planes of A** instead of Booth-recoding B. Each lane pair contributes one 4:1 multiplexer per bit plane, selecting between `0`, `b₂ⱼ`, `b₂ⱼ₊₁` and `b₂ⱼ + b₂ⱼ₊₁`. That fourth input — the pair sum — is a function of **B alone**.

This gate is where it is computed. Because it is a function of B alone it belongs in the **per-column** dispatch ([disp_array_b_bpl_a_bfp](./disp_array_b_bpl_a_bfp.md)), not inside a PE: the adders are paid `N` times per grid instead of `N²` times. That amortization is the whole reason the bit-plane variant exists — see [PE Grid (Bit-Plane-A BFP)](../architectures/top_NxN_bpl_a_bfp.md).

Emitting both sets **already resolved to signed values** is what lets `dp_8_bpl_a_bfp` drop its `is_signed_b_i` port entirely: B's signedness is consumed here, once per column, and never reaches the PEs.

Contrast [gate_b_n](./gate_b_n.md), the pass/zero/negate conditioning gate that sits *upstream* of this one — this gate does no conditioning of its own, it widens and sums whatever the conditioning gate produced.

## Parameters

| Parameter | Default | Description                                            |
| --------- | ------- | ------------------------------------------------------ |
| `WIDTH`   | 4       | Bit width of each input word.                          |
| `SIZE`    | 8       | Number of input words — even; all share `is_signed_i`. |

Derived: `OUT_WIDTH = WIDTH + 1`, `SUM_WIDTH = WIDTH + 2`, `NUM_SUM = SIZE / 2`.

## Interface

| Signal        | Dir | Width                | Description                                                                    |
| ------------- | --- | -------------------- | ------------------------------------------------------------------------------ |
| `in_i`        | in  | `SIZE` × `WIDTH`     | Input words — unpacked array `[0:SIZE-1]`.                                     |
| `is_signed_i` | in  | 1                    | Shared signedness: `1` = words are two's complement, `0` = unsigned.           |
| `out_o`       | out | `SIZE` × `WIDTH+1`   | Each word as its exact signed value — unpacked array `[0:SIZE-1]`.             |
| `sum_o`       | out | `SIZE/2` × `WIDTH+2` | Pairwise sums (word `2k` plus word `2k+1`), signed — unpacked `[0:NUM_SUM-1]`. |

Combinational — no clock, no storage.

## Instantiation

```systemverilog
gate_n_bpl_bfp #(.WIDTH(4), .SIZE(8)) gate_n_bpl_bfp_i (
    .in_i       (nibbles),
    .is_signed_i(is_signed_b),
    .out_o      (b_values),
    .sum_o      (b_pair_sums)
);
```

## Internal logic

### Why `WIDTH+1` for a single value

One extra bit is exactly enough. A signed `WIDTH`-bit word sign-extends into `WIDTH+1` bits with no change of value; an unsigned `WIDTH`-bit word reaches `2^WIDTH − 1`, which is always representable in `WIDTH+1` bits of two's complement. So a single conditional sign bit resolves both cases:

```systemverilog
assign ext[i]   = {is_signed_i & in_i[i][WIDTH-1], in_i[i]};
assign out_o[i] = ext[i];
```

When `is_signed_i` is low the prepended bit is `0` — a zero extension. When it is high it replicates the word's MSB — a sign extension. After this point the value is unambiguously signed and no downstream consumer needs the flag again.

### Why `WIDTH+2` for a pair sum

Two bits of growth are required, **not one**, and the reason is that the two signedness cases push the sum in opposite directions:

- **unsigned pair:** `2 · (2^WIDTH − 1)` — for `WIDTH = 4` that is `30`, which does not fit in `WIDTH+1 = 5` bits of two's complement (max `+15`).
- **signed pair:** `2 · (−2^(WIDTH−1))` = `−2^WIDTH` — for `WIDTH = 4` that is `−16`.

`WIDTH+2` bits span `[−32, +31]` at `WIDTH = 4` and covers both. The sum is formed by widening the already-resolved values one more bit with [ext_n](./ext_n.md) and adding with [add_n](./add_n.md), keeping the carry-out so the result is exact:

```systemverilog
ext_n #(.WIDTH(OUT_WIDTH), .SIZE(SIZE), .EXT(1), .IS_SIGNED(1'b1)) ext_n_i (
    .in_i(ext), .out_o(ext_w)
);

add_n #(.WIDTH(OUT_WIDTH), .CARRY(1)) add_n_i (
    .in_0_i(ext_w[2*k+0]), .in_1_i(ext_w[2*k+1]), .cin_i(add_cin[k]),
    .out_o (add_sum[k]),   .cout_o(add_cout[k])
);

assign sum_o[k] = {add_cout[k], add_sum[k]};
```

The `ext_n` widening is what makes the `add_n` exact: adding two `WIDTH+1`-bit signed values in `WIDTH+1` bits would wrap, so both are sign-extended to `WIDTH+2` first and the adder's carry-out becomes the sum's top bit.

### Pairing is fixed, and it has to be

Words pair as `(0,1)`, `(2,3)`, `(4,5)`, `(6,7)` — the same adjacency the DP8's lane pairs use, so `sum_o[k]` is exactly what lane pair `k`'s multiplexer wants on its `11` input. The pairing never crosses a DP8 boundary, which matters for the complex modes: the two's-complement negate carry chained by the upstream [gate_b_n](./gate_b_n.md) crosses the **H/L half** boundary, never a lane pair, so a negated operand still pairs correctly.

### Why this gate sits *after* the conditioning gate

Order matters. The sums must be of the values the DP8 actually multiplies — zeroed for an idle lane, negated for a complex-mode imaginary term. Placing this gate before [gate_b_n](./gate_b_n.md) would sum the raw nibbles and the multiplexer's `11` input would disagree with its `01`/`10` inputs. In [disp_array_b_bpl_a_bfp](./disp_array_b_bpl_a_bfp.md) it is therefore instantiated strictly downstream of the conditioning gate.

## Verification

Exercised through [tb_disp_array_bpl_a_bfp](../testbenches/tb_disp_array_bpl_a_bfp.md), whose golden model reproduces the widening and the four pairwise sums for all 11 modes — including the negate modes driven with the real carry-chained control, so the sums are checked on genuinely negated operands.

Source: [gate_n_bpl_bfp.sv](../../rtl/gate_n_bpl_bfp.sv)
