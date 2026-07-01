---
type: module
title: Register N
description: Parameterized register bank — SIZE independent WIDTH-bit registers with a shared async active-low reset.
resource: rtl/reg_n.sv
tags: [module, state, register]
timestamp: 2026-07-01
---

# Register N

`reg_n` — Parameterized register-bank primitive: `SIZE` independent `WIDTH`-bit registers with a shared asynchronous active-low reset.

## Purpose

Holds `SIZE` independent `WIDTH`-bit registers behind one module, providing the PE's pipeline and accumulator registers from a single parameterized source. There is no enable — each register loads every cycle, so any hold or accumulate behavior is provided by upstream logic feeding `d_i`.

## Parameters

| Parameter | Default | Description                      |
| --------- | ------- | -------------------------------- |
| `WIDTH`   | 8       | Bit width of each register.      |
| `SIZE`    | 4       | Number of registers in the bank. |

## Interface

| Signal   | Dir | Width            | Description                                               |
| -------- | --- | ---------------- | -------------------------------------------------------- |
| `clk_i`  | in  | 1                | Clock; registers update on the rising edge.              |
| `rst_ni` | in  | 1                | Asynchronous active-low reset; clears all registers to 0.|
| `d_i`    | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`.               |
| `q_o`    | out | `SIZE` × `WIDTH` | Registered outputs — unpacked array `[0:SIZE-1]`.       |

## Internal logic

A single `always_ff` triggered on `posedge clk_i` or `negedge rst_ni`: on reset (`rst_ni == 0`) every `q_o[i]` is asynchronously cleared to `'0`; otherwise on each rising clock edge every `q_o[i]` captures `d_i[i]`. All `SIZE` registers share `clk_i` and `rst_ni`.

## Instantiation

```systemverilog
reg_n #(.WIDTH(8), .SIZE(4)) reg_n_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(d), .q_o(q)
);
```

Source: [reg_n.sv](../../rtl/reg_n.sv)
