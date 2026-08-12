# Dot Product 8 (Bit-Plane-A BFP) Testbench

## Purpose

`tb_dp_8_bpl_a_bfp` verifies [dp_8_bpl_a_bfp](../modules/dp_8_bpl_a_bfp.md) against a [dp_8](../modules/dp_8.md) fed the same raw operands, under all four per-operand signedness combinations. The bench **owns the dispatcher-side operand preparation**: it derives the 5-bit exact values and the 6-bit pair sums from the raw int4 nibbles exactly as [gate_n_bpl_bfp](../modules/gate_n_bpl_bfp.md) does, so the DUT is exercised through the same contract it sees in the grid.

## Parameters

| Parameter  | Default | Description                                                        |
| ---------- | ------- | ------------------------------------------------------------------ |
| `NUM_RAND` | `2000`  | Random `(a, b)` vector pairs, each checked in 4 signedness combos. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=dp_8_bpl_a_bfp
```

## What it checks

| Property             | Check                                                                             |
| -------------------- | --------------------------------------------------------------------------------- |
| **resolve**          | `sum_o + carry_o == Σₖ aₖ·bₖ` modulo `2^OUT_WIDTH`.                               |
| **sign-consistency** | `signext(sum_o) + signext(carry_o) == Σₖ aₖ·bₖ` — the strictly stronger property. |
| **equivalence**      | the value equals that of a `dp_8` given the same raw operands.                    |

Any mismatch is **fatal**.

## How it checks

### Why sign-consistency is the gating property

The tree above the DP8 sign-extends and re-aligns the carry-save pair, so a merely *resolving* pair is not enough — the extension has to be valid. `cpr_w_n` drops any carry out of its top bit, so the property holds only while `2^(W−1) > Σ|rows|` at every stage.

In [dp_8_bpl_a_bfp](../modules/dp_8_bpl_a_bfp.md) the tightest stage sits **~6 % inside** that bound: a resolved B element spans `[−8, 15]`, so a pair sum spans `[−16, 30]` and the four rows of a per-column 4:2 reach `Σ|rows| ≤ 120` against `2⁷ = 128`. That margin is too small to call the property structural, so it is **established here by simulation** rather than by construction.

### Corner-biased stimulus

Because the bound is only reached at the extremes, lanes are biased toward the most-negative / max-positive / all-ones values rather than drawn uniformly — a uniform distribution needs far more vectors to hit the same corners. Directed corner cases run on top of the random draws.

### The signedness sweep

Each random `(a, b)` pair is checked four times, once per `(is_signed_a, is_signed_b)` combination. `is_signed_b` never reaches the DUT — the bench applies it when it derives the 5-bit values and pair sums, mirroring the dispatcher — while `is_signed_a` drives the DUT's weight-2⁷ correction directly, so the one's-complement + `+2⁸` fold is exercised in both states.

Result: **all 2000 random + corner tests PASSED**, 0 mismatches.

Source: [tb_dp_8_bpl_a_bfp.sv](../../tb/tb_dp_8_bpl_a_bfp.sv) — DUT: [dp_8_bpl_a_bfp](../modules/dp_8_bpl_a_bfp.md) (reference: [dp_8](../modules/dp_8.md))
