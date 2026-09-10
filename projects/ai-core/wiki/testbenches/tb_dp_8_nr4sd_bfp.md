# Dot Product 8 (NR4SD BFP) Testbench

## Purpose

`tb_dp_8_nr4sd_bfp` verifies [dp_8_nr4sd_bfp](../modules/dp_8_nr4sd_bfp.md) against a golden dot product, under both `is_signed_a` states. The DUT consumes per-lane digit codes, so the bench **owns the dispatcher-side operand preparation**: it recodes each nibble with a software model written from the arithmetic definition of the hybrid — never from the boolean equations [nr4sd_r4](../modules/nr4sd_r4.md) implements — and packs the digits into codes by value tables, so the core is exercised through the same contract it sees in the grid. There is no [dp_8](../modules/dp_8.md) reference at this level.

## Parameters

| Parameter  | Default | Description                                                             |
| ---------- | ------- | ----------------------------------------------------------------------- |
| `NUM_RAND` | `2000`  | Random vectors per experiment, each checked in 2 `a`-signedness states. |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=dp_8_nr4sd_bfp
```

## What it checks

| Property             | Check                                                                               |
| -------------------- | ----------------------------------------------------------------------------------- |
| **resolve**          | `sum_o + carry_o == golden` modulo `2^OUT_WIDTH`.                                   |
| **sign-consistency** | `signext(sum_o) + signext(carry_o) == golden` — the strictly stronger property.     |
| **recoded lanes**    | golden `Σₖ aₖ·(signed(bₖ) + c_inₖ)` on nibbles recoded by the software model.        |
| **raw code space**   | golden `Σₖ aₖ·(d₀ₖ + 4·d₁ₖ)` on codes and windows drawn directly, over `[−9, +10]`.  |

Any mismatch is **fatal**.

## How it checks

### Two experiments, one contract

The first experiment draws `(a, b, c_in)` per lane and recodes the nibble as the dispatcher would — NR4SD⁺ on the low pair with the carry-in, Booth on the top pair with the carry the low pair produced:

```systemverilog
s = int'({b[1], b[0]}) + int'(cin);
if (s >= 3) begin
    d0 = s - 4;
    c1 = 1;
end else begin
    d0 = s;
    c1 = 0;
end
d1    = -2 * int'(b[3]) + int'(b[2]) + c1;
code0 = enc_nr4sd(d0);
sel1  = enc_booth(d1);
```

`enc_booth` picks **either** window for `±1` at random (`001`/`010`, `101`/`110`), so both encodings of the same digit reach the cell. The golden is `Σₖ aₖ·(signed(bₖ) + c_inₖ)` — the cross-nibble carry is the `+1` — and `c_in` is drawn per lane, so both link states are exercised together with the sign of every nibble.

The second experiment skips the nibble: every 2-bit code and every 3-bit window is legal, so it drives the code space directly and checks `Σₖ aₖ·(d₀ₖ + 4·d₁ₖ)` with the digits decoded by the cells' tables. That reaches the full `[−9, +10]` lane range — values no real nibble produces — and stresses the guard bits harder than the recoded path can.

### Sign-consistency

The tree above the DP8 sign-extends and re-aligns the carry-save pair, so a merely *resolving* pair is not enough. `cpr_w_n` drops any carry out of its top bit, so the property holds only while `2^(W−1) > Σ|rows|` at every stage; with four final rows instead of six the margin is wider than `dp_8`'s, and the bench still checks it on every vector, because it is what the array above depends on:

```systemverilog
if ((longint'($signed(sum)) + longint'($signed(carry))) !== exp) begin
    $error("%s SIGN-EXTEND MISMATCH sa=%0d exp=%0d (sum=%0d carry=%0d): not sign-consistent",
           tag, sgn_a, exp, $signed(sum), $signed(carry));
    $fatal;
end
```

### Corner-biased stimulus

Lanes are biased toward the most-negative / max-positive values of A and B rather than drawn uniformly, and the code-space draws are biased toward the extreme digit pairs (`+2` with `+2`, `−1` with `−2`, `+2` with `−2`), so the compressor guard bits are exercised at their bounds. Directed corners run on top: every A/B extreme pairing (including all-ones) under both carry-ins for the recoded path, and the extreme code pairs against `A_MAX_POS`, `A_MIN_NEG` and all-ones for the code path.

### Why there is no `dp_8` reference

An unsigned nibble is not representable by a lone two-digit DP8 — its DP8 is off by `−16·b₃·A` by design, the nibble above carrying the compensation. Equivalence with the Booth baseline is therefore checked one level up, in [tb_pe_array_nr4sd_bfp](./tb_pe_array_nr4sd_bfp.md), where the nibbles of an element have been recombined.

Result: **all 2000 recoded + 2000 code-space random + corner tests PASSED**, 0 mismatches.

Source: [tb_dp_8_nr4sd_bfp.sv](../../tb/tb_dp_8_nr4sd_bfp.sv) — DUT: [dp_8_nr4sd_bfp](../modules/dp_8_nr4sd_bfp.md)
