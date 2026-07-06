---
type: experiment
title: Cascade Compressor N Testbench
description: Self-checking testbench for cpr_c_n — the carry-save output must resolve to the arithmetic sum of the inputs.
resource: tb/tb_cpr_c_n.sv
---

# Cascade Compressor N Testbench

## Purpose

`tb_cpr_c_n` is the self-checking testbench for [cpr_c_n](../modules/cpr_c_n.md) — the serial-cascade (min-area) sibling of [cpr_w_n](../modules/cpr_w_n.md), verified identically. It checks that the carry-save pair `sum_o + carry_o` resolves to the arithmetic sum of all inputs (modulo `2^OUT_WIDTH`) for `NUM_RAND` random vectors plus directed corners, once per compile-time `IS_SIGNED` value.

## Parameters

| Parameter   | Default | Description                                         |
| ----------- | ------- | --------------------------------------------------- |
| `IN_WIDTH`  | `8`     | Bit width of each input word (forwarded to the DUT) |
| `IN_SIZE`   | `8`     | Number of input words (forwarded to the DUT)        |
| `IS_SIGNED` | `1'b1`  | Input signedness (forwarded to the DUT)             |
| `NUM_RAND`  | `2000`  | Number of random vectors                            |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=cpr_c_n PARAMS="IS_SIGNED=1"
make sim PROJECT=ai-core TOP_LEVEL=cpr_c_n PARAMS="IS_SIGNED=0"
```

## What it checks

| Property   | Check                                                                          |
| ---------- | ------------------------------------------------------------------------------ |
| Resolve    | `sum_o + carry_o == Σ in_i` (modulo `2^OUT_WIDTH`)                             |
| Signedness | inputs sign/zero-extended per the compile-time `IS_SIGNED`; run once per value |

Random vectors + directed corners; **fatal** on any mismatch; dumps `activity.vcd`. Run twice — once with `IS_SIGNED=1`, once with `IS_SIGNED=0`.

## How it checks

The internal logic is the same as [tb_cpr_w_n](cpr_w_n.md): only the instantiated DUT differs (`cpr_c_n` in place of `cpr_w_n`), since both compressors implement the same N-input arithmetic and differ only in their internal topology (serial cascade vs. Wallace tree).

### Stimulus generation

The output width is derived as `OUT_WIDTH = IN_WIDTH + $clog2(IN_SIZE)` — wide enough to hold the sum of `IN_SIZE` words without overflow. The main loop fills all `IN_SIZE` input words with independent random draws and checks each vector:

```systemverilog
task automatic rand_vec;
    for (int i = 0; i < IN_SIZE; i++) in_v[i] = IN_WIDTH'($urandom);
endtask

for (int t = 0; t < NUM_RAND; t++) begin
    rand_vec;
    check();
end
```

After the random phase, four directed corners drive *every* input word to the same boundary pattern via `set_vec` — all-zero, all-ones, max-positive (`{1'b0, all-ones}`), and min-negative (`{1'b1, all-zeros}`) — exercising the cascade at its arithmetic extremes and at the sign boundary:

```systemverilog
set_vec(ZERO);     check();
set_vec(ALL_ONES); check();
set_vec(MAX_POS);  check();
set_vec(MIN_NEG);  check();
```

### Golden reference model

`check` computes the expected sum independently of the DUT by accumulating the inputs in a full-width `longint`. Each word is interpreted as signed or unsigned according to the *same* compile-time `IS_SIGNED` the DUT was built with — this is how signedness is handled on the reference side and it must match the DUT's internal extension:

```systemverilog
task automatic check;
    ...
    #1;
    exp  = 0;
    mask = (longint'(1) << OUT_WIDTH) - 1;
    for (int i = 0; i < IN_SIZE; i++) begin
        if (IS_SIGNED) exp += longint'($signed(in_v[i]));
        else           exp += longint'($unsigned(in_v[i]));
    end
```

`exp` is the golden arithmetic sum, computed by plain `longint` addition with no reference to the DUT's outputs. The DUT emits a carry-save pair rather than a single number, so the testbench *resolves* it back to one value by adding the two vectors — `sum + carry` is the DUT's result in ordinary binary:

```systemverilog
    res = sum + carry;
```

### Compare and reporting

Because the golden `exp` is full precision while the DUT wraps at `OUT_WIDTH`, the comparison masks the golden value into the same modulus (`exp & mask`) before the exact `!==` compare. Any bit mismatch, or any `x`/`z` on the outputs, trips it. On failure the dump is stopped, the expected/got values and the raw sum/carry pair are printed, and the run aborts:

```systemverilog
    if (res !== OUT_WIDTH'(exp & mask)) begin
        $dumpoff;
        $error("MISMATCH is_signed=%0d exp=%0d got=%0d (sum=%0d carry=%0d)",
               IS_SIGNED, exp, res, sum, carry);
        $fatal;
    end
```

If every random vector and corner passes, the run prints `cpr_c_n: all N random + corner tests PASSED!` and `$finish`es. Signedness is not swept inside the run — because `IS_SIGNED` is a compile-time parameter, full coverage requires the two builds shown in [Run](#run).

Source: [tb_cpr_c_n.sv](../../tb/tb_cpr_c_n.sv) — DUT: [cpr_c_n](../modules/cpr_c_n.md)
