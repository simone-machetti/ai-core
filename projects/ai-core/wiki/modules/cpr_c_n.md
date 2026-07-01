---
type: module
title: Cascade Compressor N
description: N-to-2 carry-save compressor, serial-cascade build (minimal area).
resource: rtl/cpr_c_n.sv
tags: [module, arithmetic, compressor, carry-save]
timestamp: 2026-07-01
---

# Cascade Compressor N

`cpr_c_n` — Parameterized N-to-2 carry-save compressor, cascade build: reduces `IN_SIZE` `IN_WIDTH`-bit inputs to two outputs whose sum equals the sum of all inputs.

## Purpose

Sums a group of values into redundant carry-save form (`sum_o`, `carry_o`) with minimal area, at the cost of latency that grows linearly with `IN_SIZE`. It shares its interface with the Wallace build [cpr_w_n](cpr_w_n.md); pick between them by the area versus throughput trade-off. `EXT` sets the headroom that keeps the running sum from wrapping, and one guard bit above that (`EXT = clog2(IN_SIZE) + 1`) makes the `(sum, carry)` pair sign-consistent — sign-extending the two rows and adding still equals the value — which is what lets the DP re-align carry-save pairs.

## Parameters

| Parameter   | Default           | Description                                             |
| ----------- | ----------------- | ------------------------------------------------------- |
| `IN_WIDTH`  | 8                 | Bit width of each input word.                           |
| `IN_SIZE`   | 8                 | Number of input words to compress.                      |
| `EXT`       | `$clog2(IN_SIZE)` | Extra headroom bits added on top of `IN_WIDTH`.        |
| `IS_SIGNED` | `1`               | Input extension: `1` = sign-extend, `0` = zero-extend. |

`OUT_WIDTH` (derived) `= IN_WIDTH + EXT`. `IS_SIGNED` is compile-time because a compressor's signedness is fixed by its datapath position, never switched at runtime.

## Interface

| Signal    | Dir | Width                  | Description                                                    |
| --------- | --- | ---------------------- | ------------------------------------------------------------- |
| `in_i`    | in  | `IN_SIZE` × `IN_WIDTH` | Input words — unpacked array `[0:IN_SIZE-1]`.                 |
| `sum_o`   | out | `OUT_WIDTH`            | Carry-save sum row.                                           |
| `carry_o` | out | `OUT_WIDTH`            | Carry-save carry row; `sum_o + carry_o` = Σ inputs (mod 2^W). |

## Internal logic

Each input is first extended from `IN_WIDTH` to `OUT_WIDTH` by [ext_n](ext_n.md) (sign- or zero-extended per `IS_SIGNED`). The running `(sum, carry)` pair is seeded directly from the first two extended inputs — any two numbers already form a carry-save pair — and the remaining inputs are then absorbed one at a time through a cascade of 3:2 stages, each a row of `OUT_WIDTH` full adders [fa](fa.md) whose carry row is shifted up by one bit. After `IN_SIZE − 2` stages the running pair is the result. Purely combinational; no clock, no storage.

## Instantiation

```systemverilog
cpr_c_n #(.IN_WIDTH(10), .IN_SIZE(8), .EXT(4), .IS_SIGNED(1'b1)) cpr_c_n_i (
    .in_i(in), .sum_o(sum), .carry_o(carry)
);
```

Source: [cpr_c_n.sv](../../rtl/cpr_c_n.sv) — Testbench: [tb_cpr_c_n.sv](../../tb/tb_cpr_c_n.sv)
