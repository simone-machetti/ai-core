# Gate N

`gate_n` — Parameterized zero gate: passes or forces to zero a group of `SIZE` `WIDTH`-bit words under a shared 1-bit select.

## Purpose

Conditionally masks a group of words to zero — used for operand masking, which only ever needs zeroing, never negation (contrast [gate_b_n](gate_b_n.md)), and at small `WIDTH` as a carry enable. In [acc_array](../architecture/acc_array.md) it gates the inter-lane fusion carry (`WIDTH = 2`, `SIZE = 4`): drive `sel_i = ~prop_carry` so the carry passes only when a lane pair fuses.

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
gate_n #(.WIDTH(8), .SIZE(4)) gate_n_i (
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

### The carry-enable case

At narrow `WIDTH` the same "pass or force to zero" behavior reads as a carry enable. In [acc_array](../architecture/acc_array.md) one `gate_n #(.WIDTH(2), .SIZE(4))` gates the four inter-lane fusion carries: with `sel_i = ~prop_carry`, `prop_carry = 1` lets each 2-bit carry propagate from the low lane to the high lane of a pair, `prop_carry = 0` forces it to `0` so the lanes stay independent. Masking to zero — never negation — is all this conditioning ever needs, which is why it uses `gate_n` and not the richer [gate_b_n](gate_b_n.md).

Source: [gate_n.sv](../../rtl/gate_n.sv)
