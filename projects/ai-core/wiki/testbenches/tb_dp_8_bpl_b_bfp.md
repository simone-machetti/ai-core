# Dot Product 8 (Bit-Plane-B BFP) Testbench

## Purpose

`tb_dp_8_bpl_b_bfp` verifies [dp_8_bpl_b_bfp](../modules/dp_8_bpl_b_bfp.md) against a [dp_8](../modules/dp_8.md) fed the same raw operands, under all four per-operand signedness combinations. The bench **owns the dispatcher-side operand preparation**: it derives the 9-bit exact values and the 10-bit pair sums from the raw int8 lanes exactly as [gate_n_bpl_bfp](../modules/gate_n_bpl_bfp.md) does, so the DUT is exercised through the same contract it sees in the grid.

## Parameters

| Parameter  | Default | Description                                                        |
| ---------- | ------- | ------------------------------------------------------------------ |
| `NUM_RAND` | `2000`  | Random `(a, b)` vector pairs, each checked in 4 signedness combos. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=dp_8_bpl_b_bfp
```

## What it checks

| Property             | Check                                                                             |
| -------------------- | --------------------------------------------------------------------------------- |
| **resolve**          | `sum_o + carry_o == Σₖ aₖ·bₖ` modulo `2^OUT_WIDTH`.                               |
| **sign-consistency** | `signext(sum_o) + signext(carry_o) == Σₖ aₖ·bₖ` — the strictly stronger property. |
| **equivalence**      | the value equals that of a `dp_8` given the same raw operands.                    |

Any mismatch is **fatal**.

## How it checks

### Sign-consistency, with more room than the A build

The tree above the DP8 sign-extends and re-aligns the carry-save pair, so a merely *resolving* pair is not enough. `cpr_w_n` drops any carry out of its top bit, so the property holds only while `2^(W−1) > Σ|rows|` at every stage.

Where [tb_dp_8_bpl_a_bfp](./tb_dp_8_bpl_a_bfp.md) had to establish this by simulation — its tightest stage sat 6 % inside the bound — the B build's per-plane 4:2 sits at **50 %** of its bound (`Σ|rows| ≤ 2040` against `2¹² = 4096`). The property is comfortable here; the bench still checks it on every vector, because it is what the array above depends on.

### Corner-biased stimulus

Lanes are biased toward the most-negative / max-positive / all-ones values rather than drawn uniformly, so the compressor guard bits are exercised at their bounds rather than near the middle of the range. Directed corner cases run on top of the random draws.

### The signedness sweep

Each random `(a, b)` pair is checked four times, once per `(is_signed_a, is_signed_b)` combination. Roles are the reverse of the A build: `is_signed_a` never reaches the DUT — the bench applies it when it derives the 9-bit values and pair sums, mirroring [disp_array_a_bpl_b_bfp](../modules/disp_array_a_bpl_b_bfp.md) — while `is_signed_b` drives the DUT's weight-2³ correction directly, so the one's-complement + `+2⁴` fold is exercised in both states.

Result: **all 2000 random + corner tests PASSED**, 0 mismatches.

Source: [tb_dp_8_bpl_b_bfp.sv](../../tb/tb_dp_8_bpl_b_bfp.sv) — DUT: [dp_8_bpl_b_bfp](../modules/dp_8_bpl_b_bfp.md) (reference: [dp_8](../modules/dp_8.md))
