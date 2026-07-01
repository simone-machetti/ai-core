---
type: module
title: Wallace Compressor N
description: N-to-2 carry-save compressor, Wallace-tree build (maximal throughput).
resource: rtl/cpr_w_n.sv
tags: [module, arithmetic, compressor, carry-save, wallace]
timestamp: 2026-07-01
---

# Wallace Compressor N

`cpr_w_n` — Parameterized N-to-2 carry-save compressor, Wallace-tree build: reduces `IN_SIZE` `IN_WIDTH`-bit inputs to two outputs whose sum equals the sum of all inputs.

## Purpose

Sums a group of values into redundant carry-save form (`sum_o`, `carry_o`) with the lowest latency — rows are compressed in parallel layers, giving logarithmic depth — to maximize throughput. It shares its interface with the cascade build [cpr_c_n](cpr_c_n.md), and is the compressor used throughout the DP8 (as the 8:2 per-weight and 6:2 final reducers). `EXT` sets the headroom that keeps the running sum from wrapping, and one guard bit above that (`EXT = clog2(IN_SIZE) + 1`) makes the `(sum, carry)` pair sign-consistent — `signext(sum) + signext(carry)` still equals the value — which the DP relies on to sign-extend and re-align carry-save pairs.

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

Each input is first extended from `IN_WIDTH` to `OUT_WIDTH` by [ext_n](ext_n.md) (sign- or zero-extended per `IS_SIGNED`). The `IN_SIZE` rows are then reduced in parallel layers: each layer splits the current rows into disjoint groups of three and compresses each group to two with a row of `OUT_WIDTH` full adders [fa](fa.md) whose carry row is shifted up one bit, passing any one or two leftover rows through unchanged, until two rows remain. Depth is `~log_1.5(IN_SIZE)`. Purely combinational; no clock, no storage.

## Instantiation

```systemverilog
cpr_w_n #(.IN_WIDTH(10), .IN_SIZE(8), .EXT(4), .IS_SIGNED(1'b1)) cpr_w_n_i (
    .in_i(in), .sum_o(sum), .carry_o(carry)
);
```

Source: [cpr_w_n.sv](../../rtl/cpr_w_n.sv) — Testbench: [tb_cpr_w_n.sv](../../tb/tb_cpr_w_n.sv)
