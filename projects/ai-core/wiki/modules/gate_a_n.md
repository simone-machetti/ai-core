---
type: module
title: Gate A N
description: Parameterized zero gate — passes or forces to zero SIZE WIDTH-bit words under a shared 1-bit select.
resource: rtl/gate_a_n.sv
---

# Gate A N

`gate_a_n` — Parameterized zero gate: passes or forces to zero a group of `SIZE` `WIDTH`-bit words under a shared 1-bit select.

## Purpose

Conditionally masks a group of words to zero — the operand-A gating path, which only ever needs masking to zero, never negation (contrast [gate_b_n](gate_b_n.md)). At `WIDTH = 1` the same cell serves as a carry enable.

## Parameters

| Parameter | Default | Description                             |
| --------- | ------- | --------------------------------------- |
| `WIDTH`   | 8       | Bit width of each word.                 |
| `SIZE`    | 4       | Number of words (all share the select). |

## Interface

| Signal  | Dir | Width            | Description                                |
| ------- | --- | ---------------- | ------------------------------------------ |
| `in_i`  | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`. |
| `sel_i` | in  | 1                | `0` = pass, `1` = zero.                    |
| `out_o` | out | `SIZE` × `WIDTH` | Gated words — unpacked array `[0:SIZE-1]`. |

## Instantiation

```systemverilog
gate_a_n #(.WIDTH(8), .SIZE(4)) gate_a_n_i (
    .in_i  (in),
    .sel_i (sel),
    .out_o (out)
);
```

## Internal logic

The block is purely combinational — no clock, no reset, no storage. The output is produced entirely by a `generate` loop that replicates one 2:1 mux per word.

### Structure: one mux per word, one shared select

```systemverilog
genvar i;
generate
    for (i = 0; i < SIZE; i++) begin : gen_gate
        assign out_o[i] = sel_i ? '0 : in_i[i];
    end
endgenerate
```

`SIZE` copies of the same continuous assignment are elaborated, indexed `i = 0 .. SIZE-1`. Each copy drives one `WIDTH`-bit output word `out_o[i]` from the matching input word `in_i[i]`. All copies read the single, shared 1-bit `sel_i`, so the whole bank switches together — there is no per-word select.

### The per-word decision

For each word the ternary chooses between two cases:

- `sel_i == 0` (pass): `out_o[i] = in_i[i]` — the input word flows straight through, unchanged.
- `sel_i == 1` (zero): `out_o[i] = '0` — the word is forced to all zeros. `'0` is a width-agnostic literal, so every one of the `WIDTH` bits is cleared regardless of `WIDTH`.

Because the assignment is combinational, `out_o` tracks `in_i` and `sel_i` with no latency; whenever an input changes the corresponding output settles immediately.

### Sign and width handling

None is needed. Zeroing is a bitwise mask and passing is a straight copy, so the operation is identical for signed and unsigned data — there is no arithmetic, no carry, and no sign extension. `WIDTH` only sets how many bits each word carries; `SIZE` only sets how many words the loop instantiates.

### The `WIDTH = 1` carry-enable case

When instantiated with `WIDTH = 1`, each word is a single bit and the same "pass or force to zero" behavior reads as a carry enable: `sel_i = 0` lets the bit propagate, `sel_i = 1` masks it to `0`. This is why the operand-A path never needs the richer negate/carry logic of [gate_b_n](gate_b_n.md) — masking to zero is the only conditioning operand A ever requires.

Source: [gate_a_n.sv](../../rtl/gate_a_n.sv)
