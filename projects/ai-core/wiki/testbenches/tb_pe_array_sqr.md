# PE Array (Square) Testbench

## Purpose

`tb_pe_array_sqr` verifies [pe_array_sqr](../modules/pe_array_sqr.md) **driven through the square dispatchers** [disp_array_a_sqr](../modules/disp_array_a_sqr.md) + [disp_array_b_sqr](../modules/disp_array_b_sqr.md) — the same `disp → array` structure as [tb_pe_array](./tb_pe_array.md). For each of the 11 modes it pushes `NUM_RAND` corner-biased random 256-bit operands, lets the dispatchers center/idle-zero them, and checks every tap at the mode's read level against a golden that recomputes the tree.

This gate verifies the **tree** — weights, crossed pairing, the relocated negate, and the widths. The `+2`-per-negated-block correction and the α/β/C reconstruction are the accumulator's concern (a later gate).

## Parameters

| Parameter  | Default | Description                      |
| ---------- | ------- | -------------------------------- |
| `NUM_RAND` | `200`   | Random operand vectors per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_sqr
```

## What it checks

| Property         | Check                                                                              |
| ---------------- | ---------------------------------------------------------------------------------- |
| Tree correctness | every read-level tap resolves (`$signed(sum) + $signed(carry)`) to the golden tree |

Any mismatch is **fatal**.

## How it checks

### Control vectors

The mode tables carry `SEL_A`/`SEL_B` (block routing), `IS_SIGNED_A`/`IS_SIGNED_B` and `ZERO_I_LUT` (per-DP8, driving the dispatchers' centering + idle-zero — copied from [tb_disp_array_sqr](./tb_disp_array_sqr.md), including the mode-5 `is_signed_b` idle fix), plus three new tree controls:

- `NEG_I[mi]` — the 6-bit block negate: `10 → 6'b110011`, `11 → 6'b001111`, all others `0`.
- `SEL_SHIFT_LUT[mi]` — the 3-bit per-level shift enable (`000/010/011/111` by precision).
- `TAP_LEVEL[mi]` — which level the mode reads (0/1/2/3).

### The golden

For each vector the golden reads the **dispatched** (centered, idle-zeroed) `a_dp8`/`b_dp8` straight off the DUT inputs, so the dispatcher and the tree are checked as one path:

1. `sd[i] = sdp8(a_dp8[i], b_dp8[i])` — the golden square-sum `Σ 16·(AH+b)² + (AL+b)²` per DP8.
2. `blk[i] = negd[i] ? (−sd[i] − 2) : sd[i]` — apply the block negate, where a negated block resolves to `−S_DP8 − 2` (the deferred `+2` being `acc_array_sqr`'s job). `negd` maps `NEG_I[mi]` onto the six negatable DP8s: `negd[2]=[0]`, `negd[3]=[1]`, `negd[6]=[2]`, `negd[7]=[3]`, `negd[10]=[4]`, `negd[11]=[5]`.
3. Reduce the 16 `blk` through the crossed 4-level tree with weights `(1<<SH0)`/`(1<<SH1)`/`(1<<SH2)` gated by `SEL_SHIFT_LUT[mi]` — the same crossed L0 pairing and adjacent L1/L2/L3 pairing as the RTL.
4. Compare `resolve_tap(TAP_LEVEL[mi], node)` against the golden node value for every node at the read level.

### Drive/sample timing

`pe_array_sqr` registers at L0 (and the dispatchers register their input), so each vector is applied and clocked `repeat(2) @(posedge clk_i); #1;` before the taps are sampled. Operands are corner-biased (`0x00`/`0xFF`/`0x80`/`0x7F`/`0x88` bytes mixed with uniform random) to stress sign-consistency at the square-sum boundary.

If every vector passes, the tb prints `pe_array_sqr: all 11 modes x 200 random tests PASSED!` and calls `$finish`. Verified: 11 modes × 200 vectors, 0 mismatches, `-Wall` clean.

Source: [tb_pe_array_sqr.sv](../../tb/tb_pe_array_sqr.sv) — DUT: [pe_array_sqr](../modules/pe_array_sqr.md) (through [disp_array_a_sqr](../modules/disp_array_a_sqr.md) + [disp_array_b_sqr](../modules/disp_array_b_sqr.md))
