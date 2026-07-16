# PE Array Beta (Square) Testbench

## Purpose

`tb_pe_array_beta_sqr` verifies [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md) **driven through the square B dispatcher** [disp_array_b_sqr](../modules/disp_array_b_sqr.md) — the same `disp → array` structure as [tb_pe_array_sqr](./tb_pe_array_sqr.md). For each of the 11 modes it pushes `NUM_RAND` corner-biased random 256-bit B operands, lets the dispatcher center/idle-zero them, and checks every tap at the mode's read level against a golden that recomputes the tree.

## Parameters

| Parameter  | Default | Description                      |
| ---------- | ------- | -------------------------------- |
| `NUM_RAND` | `200`   | Random operand vectors per mode. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array_beta_sqr
```

## What it checks

| Property         | Check                                                                              |
| ---------------- | ---------------------------------------------------------------------------------- |
| Tree correctness | every read-level tap resolves (`$signed(sum) + $signed(carry)`) to the golden tree |

Any mismatch is **fatal**.

## How it checks

The golden reads the **dispatched** (centered) `b_dp8` off the DUT and applies the β bias per DP8, checking the dispatcher, the β DP8 bias ([gate_n_sqr](../modules/gate_n_sqr.md) high / [gate_n_beta_sqr](../modules/gate_n_beta_sqr.md) low) and the tree as one path:

```
BETA_DP8 = Σ_k 16·(B_k − 8·au)² + (idle ? 0 : (B_k − 8))²        au = ~is_signed_a
```

where the high block is `is_signed_a ? B_k : B_k − 8` (mirroring `gate_n_sqr`) and the low block is `zero ? 0 : B_k − 8` (mirroring `gate_n_beta_sqr` — the **fixed** `−8` with idle-zero). Then the same block-negate (`negd ? −BETA_DP8−2 : BETA_DP8`), the crossed 4-level weighted tree, and `resolve_tap` at `TAP_LEVEL[mode]`. Mode tables are copied from [tb_pe_array_sqr](./tb_pe_array_sqr.md); the A side is dropped.

**Idle** DP8s (modes 5/6): the low block's fixed `−8` is killed by `zero_i` and the high block self-cleans via `is_signed_a = 1`, so `BETA_DP8 = 0` — this exercises the β-specific idle-leak fix.

### Drive/sample timing

The dispatcher and the β array both register, so each vector is applied and clocked `repeat(2) @(posedge clk_i); #1;` before sampling. Corner-biased operands stress the bias/sign boundary.

Verified: 11 modes × 200 vectors, 0 mismatches, `-Wall` clean — `pe_array_beta_sqr: all 11 modes x 200 random tests PASSED!`.

Source: [tb_pe_array_beta_sqr.sv](../../tb/tb_pe_array_beta_sqr.sv) — DUT: [pe_array_beta_sqr](../modules/pe_array_beta_sqr.md) (through [disp_array_b_sqr](../modules/disp_array_b_sqr.md))
