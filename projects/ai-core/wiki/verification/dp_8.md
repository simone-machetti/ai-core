---
type: experiment
title: Dot Product 8 Testbench
description: Self-checking testbench for dp_8 — verifies both resolve and sign-consistency of the carry-save dot product across all signedness combinations.
resource: tb/tb_dp_8.sv
---

# Dot Product 8 Testbench

## Purpose

`tb_dp_8` verifies [dp_8](../modules/dp_8.md), the 8-lane carry-save dot product. It drives random and directed-corner `(a, b)` vector pairs — each under all four per-operand signedness combinations — and checks two properties of the two 17-bit carry-save rows: that they *resolve* to the true dot product, and that they stay *independently sign-extendable*.

## Parameters

| Parameter  | Default | Description                                                                                                                            |
| ---------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `NUM_RAND` | `2000`  | Number of random `(a, b)` vector pairs; each is exercised under all four signedness combinations, then six directed corners are added. |

The DUT is instantiated with its defaults; the tb pins the shape with localparams `LANES=8`, `WIDTH_A=8`, `WIDTH_B=4`, `OUT_WIDTH=17` (the resolved width is 16 value bits + 1 guard bit) and does not override any DUT parameter.

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=dp_8
```

Increase the random budget with `PARAMS="NUM_RAND=10000"`.

## What it checks

| Property        | Check                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------------- |
| Resolve         | the low `OUT_WIDTH` (17) bits of `sum_o + carry_o` equal `Σ_i a_i · b_i` masked to the same width |
| Sign-consistent | `signext(sum_o) + signext(carry_o) == Σ_i a_i · b_i` exactly (full precision)                     |

The sign-consistency property is the stronger one: it guarantees the two carry-save rows can each be **sign-extended independently** by [pe_array](../architecture/pe_array.md) downstream (the reason each row carries a guard bit). A plain resolve check does not catch a lost sign; this one does. All four `is_signed_a_i × is_signed_b_i` combinations run on every vector, and any mismatch is **fatal**.

## How it checks

### Stimulus generation

`rand_vec` fills the eight `a`/`b` lanes with fresh raw random bits; the *interpretation* (signed vs unsigned) is applied later per check, so the same bit pattern is reused across all four signedness combinations.

```systemverilog
task automatic rand_vec;
    for (int i = 0; i < LANES; i++) begin
        a_v[i] = WIDTH_A'($urandom);
        b_v[i] = WIDTH_B'($urandom);
    end
endtask
```

After the random loop, `set_vec` drives six directed corners that random draws almost never hit: all-zero, both max-positive, both min-negative, the two mixed max/min pairs, and all-ones. `A_MIN_NEG`/`B_MIN_NEG` are the most-negative values (`1000…0`) — the classic sign-extension trap.

```systemverilog
set_vec(A_ZERO,     B_ZERO);      check_all;
set_vec(A_MAX_POS,  B_MAX_POS);   check_all;
set_vec(A_MIN_NEG,  B_MIN_NEG);   check_all;
set_vec(A_MAX_POS,  B_MIN_NEG);   check_all;
set_vec(A_MIN_NEG,  B_MAX_POS);   check_all;
set_vec(A_ALL_ONES, B_ALL_ONES);  check_all;
```

### The golden reference

The expected value is computed in a wide `longint` accumulator, completely outside the DUT: each lane's product is formed from the operands re-interpreted according to the signedness under test (`$signed` vs `$unsigned`), then summed. This is an independent scalar model — it never mimics the carry-save tree.

```systemverilog
exp  = 0;
mask = (longint'(1) << OUT_WIDTH) - 1;
for (int i = 0; i < LANES; i++) begin
    a_val = sgn_a ? longint'($signed(a_v[i])) : longint'($unsigned(a_v[i]));
    b_val = sgn_b ? longint'($signed(b_v[i])) : longint'($unsigned(b_v[i]));
    exp  += a_val * b_val;
end
```

### The signedness sweep

`check_all` runs `check` for every combination of the two signedness flags, so each stimulus vector is verified four ways:

```systemverilog
task automatic check_all;
    check(1'b0, 1'b0);
    check(1'b0, 1'b1);
    check(1'b1, 1'b0);
    check(1'b1, 1'b1);
endtask
```

### Drive/sample timing

`dp_8` is purely combinational, so there is no clock in this testbench. `check` drives the two signedness inputs, waits `#1` for the logic to settle, then reads `sum`/`carry` in the same delta region — no pipeline latency to account for.

### Compare and report

`check` performs both comparisons. The resolve check truncates `sum + carry` to `OUT_WIDTH` bits and compares against the golden sum masked to the same width; the sign-consistency check sign-extends each row to full precision and requires the sum to equal `exp` on the nose. Either failure calls `$dumpoff` and `$fatal`, so the run stops at the first bad vector with the operands and both values printed.

```systemverilog
res = sum + carry;
if (res !== OUT_WIDTH'(exp & mask)) begin
    $error("RESOLVE MISMATCH ...", ...); $fatal;
end
if ((longint'($signed(sum)) + longint'($signed(carry))) !== exp) begin
    $error("SIGN-EXTEND MISMATCH ...", ...); $fatal;
end
```

If every vector passes, the tb prints `dp_8: all N random + corner tests PASSED!` and calls `$finish`.

Source: [tb_dp_8.sv](../../tb/tb_dp_8.sv) — DUT: [dp_8](../modules/dp_8.md)
