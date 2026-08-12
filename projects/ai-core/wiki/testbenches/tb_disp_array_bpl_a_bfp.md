# Dispatch Array (Bit-Plane-A BFP) Testbench

## Purpose

`tb_disp_array_bpl_a_bfp` verifies the bit-plane dispatch pair — [disp_array_a](../modules/disp_array_a.md) and [disp_array_b_bpl_a_bfp](../modules/disp_array_b_bpl_a_bfp.md) — against a golden model of the whole routing and conditioning chain. It is the bit-plane counterpart of [tb_disp_array](./tb_disp_array.md), instantiating the same two dispatchers so the A route is covered alongside the B route.

The B side is where the work is: the golden reproduces block select, the fixed high/low split, the per-int4 gate **including the two's-complement carry that ripples from the low half into the high half**, the signedness-aware widening to 5 bits, and the four pairwise sums at 6 bits — i.e. everything [gate_n_bpl_bfp](../modules/gate_n_bpl_bfp.md) adds.

Unlike `tb_disp_array`, the negate modes are driven with `ctrl`'s **carry-chained** control (`GATE_NEG` on the low half, `GATE_NEG_CARRY` on the high half), so the cross-half carry is exercised and the pair sums are checked on genuinely negated operands.

## Parameters

| Parameter  | Default | Description                              |
| ---------- | ------- | ---------------------------------------- |
| `NUM_RAND` | `500`   | Random 256-bit operand vectors per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=disp_array_bpl_a_bfp
```

## What it checks

| Output            | Check                                                                                                 |
| ----------------- | ----------------------------------------------------------------------------------------------------- |
| `a_dp8[0:15]`     | equals the `SEL_A`-selected 64-bit block, duplicated across the pair.                                 |
| `b_dp8[0:15]`     | each of the 8 lanes equals the gated nibble widened by `is_signed_b` to its exact signed 5-bit value. |
| `b_sum_dp8[0:15]` | each of the 4 sums equals the signed sum of its two adjacent gated 5-bit lanes, at 6 bits.            |

Any mismatch is **fatal**.

## How it checks

### Control vectors

`SEL_A`, `SEL_B`, `CTR_L`, `CTR_H` and `IS_SIGNED_B` are taken **verbatim from `ctrl`'s lookup tables** for each of the 11 modes, so the dispatchers see their real control vectors rather than a synthetic sweep — in particular the modes where a half is zeroed (5, 6) and where an operand is negated across the half boundary (10, 11).

### The golden

Per pair, the model selects the block by `SEL_B`, splits it into eight low and eight high nibbles, and gates each with the mode's op:

```systemverilog
case (op)
    2'd1:    return {1'b0, {B_ELEM_WIDTH{1'b0}}};   // zero
    2'd2:    return {1'b0, ~x} + 1'b1;              // negate, emits carry
    2'd3:    return {1'b0, ~x} + cin;               // negate-carry, consumes it
    default: return {1'b0, x};                      // pass
endcase
```

The low half's carry-out feeds the high half's carry-in, exactly as the RTL chains it. Each gated nibble is then widened with the DP8's own `is_signed_b`, and adjacent widened lanes are summed at 6 bits — the pair sums are computed **from the golden's own widened values**, not from the DUT's, so a wrong widening cannot mask a wrong sum.

### Stimulus

Per mode: `NUM_RAND` random vectors plus one directed ramp (byte ramp on A, nibble ramp on B) that walks every element position, so a routing swap shows up even when random data happens to collide.

Result: **all 11 modes × (500 random + ramp) PASSED**, 0 mismatches.

Source: [tb_disp_array_bpl_a_bfp.sv](../../tb/tb_disp_array_bpl_a_bfp.sv) — DUTs: [disp_array_a](../modules/disp_array_a.md) + [disp_array_b_bpl_a_bfp](../modules/disp_array_b_bpl_a_bfp.md)
