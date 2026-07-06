---
type: module
title: Gate B N
description: Parameterized conditioning gate — pass / zero / negate / carry-chained negate SIZE words under a shared 2-bit select.
resource: rtl/gate_b_n.sv
---

# Gate B N

`gate_b_n` — Parameterized conditioning gate: passes, zeros, two's-complement-negates, or carry-chained-negates a group of `SIZE` `WIDTH`-bit words under a shared 2-bit select, with per-word carry-in and carry-out for chaining.

## Purpose

A 4-way mux per word — the input, an all-zero word, the input's two's-complement negation, or a carry-chained negation — for the operand-B conditioning path that needs all of these across the PE modes: pass (most modes), zeroing idle DP8s (e.g. mode 6), and sign negation (imaginary B in the complex modes). The `carry_i`/`carry_o` ports let two instances chain a two's-complement carry across a nibble boundary so an operand split across gates negates exactly. The select is shared by all `SIZE` words. Contrast [gate_a_n](gate_a_n.md), which only zeros.

## Parameters

| Parameter | Default | Description                             |
| --------- | ------- | --------------------------------------- |
| `WIDTH`   | 8       | Bit width of each word.                 |
| `SIZE`    | 4       | Number of words (all share the select). |

## Interface

| Signal    | Dir | Width            | Description                                                                            |
| --------- | --- | ---------------- | -------------------------------------------------------------------------------------- |
| `in_i`    | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`.                                             |
| `carry_i` | in  | `SIZE` × 1       | Per-word incoming carry, used only by `GATE_NEG_CARRY` — unpacked array `[0:SIZE-1]`.  |
| `sel_i`   | in  | 2                | Operation for all words: `00` = pass, `01` = zero, `10` = negate, `11` = negate-carry. |
| `out_o`   | out | `SIZE` × `WIDTH` | Gated words — unpacked array `[0:SIZE-1]`.                                             |
| `carry_o` | out | `SIZE` × 1       | Per-word negate carry-out — unpacked array `[0:SIZE-1]`.                               |

## Instantiation

```systemverilog
gate_b_n #(.WIDTH(8), .SIZE(4)) gate_b_n_i (
    .in_i    (in),
    .carry_i (carry_in),
    .sel_i   (sel),
    .out_o   (out),
    .carry_o (carry_out)
);
```

## Internal logic

The block is purely combinational — one `always_comb` with no clock and no storage. Inside it a `for` loop walks the `SIZE` words and a `case` on the shared `sel_i` picks one of four operations for every word. The four select codes are named locally:

```systemverilog
localparam logic [1:0] GATE_PASS      = 2'b00;
localparam logic [1:0] GATE_ZERO      = 2'b01;
localparam logic [1:0] GATE_NEG       = 2'b10;
localparam logic [1:0] GATE_NEG_CARRY = 2'b11;
```

Because `sel_i` is read once and applied inside the loop, all `SIZE` words always perform the *same* operation on the same cycle; only their data (and, for the carry modes, their carry) differs.

### The per-word case

```systemverilog
always_comb begin
    for (int i = 0; i < SIZE; i++) begin
        case (sel_i)
            GATE_PASS:      begin out_o[i] = in_i[i]; carry_o[i] = 1'b0; end
            GATE_ZERO:      begin out_o[i] = '0;      carry_o[i] = 1'b0; end
            GATE_NEG:       {carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + 1'b1;
            GATE_NEG_CARRY: {carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + carry_i[i];
            default:        begin out_o[i] = in_i[i]; carry_o[i] = 1'b0; end
        endcase
    end
end
```

Every branch assigns *both* `out_o[i]` and `carry_o[i]`, so the outputs are fully defined for all selects and no latch is inferred. The `default` mirrors `GATE_PASS`, so an undriven / X select degrades safely to pass-through.

### `GATE_PASS` (`00`) and `GATE_ZERO` (`01`)

The two non-arithmetic modes:

- **Pass** copies the input word straight through (`out_o[i] = in_i[i]`) and forces `carry_o[i] = 0` — there is no negation in flight, so nothing to carry.
- **Zero** drives the word to all zeros (`out_o[i] = '0`, width-agnostic) and likewise forces `carry_o[i] = 0`.

### `GATE_NEG` (`10`) — self-contained two's-complement negate

Two's complement negation is "invert every bit, then add one": `-x = ~x + 1`. The RTL builds exactly that, but widens the operand by one bit first so the add cannot silently drop its carry:

```systemverilog
{carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + 1'b1;
```

Step by step:

1. `~in_i[i]` is the bitwise inversion of the `WIDTH`-bit word.
2. `{1'b0, ~in_i[i]}` prepends a `0`, forming a `WIDTH+1`-bit value so the sum has room for a carry-out.
3. `+ 1'b1` completes the two's-complement `+1`.
4. The `WIDTH+1`-bit result is split by the concatenation on the left: the low `WIDTH` bits land in `out_o[i]` (the negated word) and the top bit lands in `carry_o[i]` (the carry-out of the `+1`).

`out_o[i]` keeps `WIDTH` bits, so the operation is modulo-`2^WIDTH`: the most-negative value (`1000…0`) negates to itself, i.e. it wraps — expected two's-complement behavior at a fixed width. In `GATE_NEG` the `+1` is a fixed, self-contained increment, so this branch negates one word exactly on its own. Its `carry_o[i]` is what a *more-significant* word would need if the operand were wider than one gate — which is exactly what the next mode consumes.

### `GATE_NEG_CARRY` (`11`) — negate that adds an incoming carry

Identical to `GATE_NEG` except the fixed `+1` is replaced by the per-word `carry_i[i]`:

```systemverilog
{carry_o[i], out_o[i]} = {1'b0, ~in_i[i]} + carry_i[i];
```

So this word inverts its bits and then adds *whatever carry arrived from below* instead of a hardwired `+1`. If `carry_i[i] = 1` it behaves like a full negate of this word; if `carry_i[i] = 0` it produces just `~in_i[i]` (the inversion with no increment). It again emits its own carry-out on `carry_o[i]` so the chain can continue to a still-higher word.

### Why the carry ports exist: chaining a negate across a nibble boundary

A single `WIDTH`-bit negate is exact on its own. The problem is an operand that is *split across several gate instances* — for example an int8 B carried as its high and low int4 nibbles in two different `gate_b_n` instances. You cannot negate each nibble independently, because the two's-complement `+1` is a single carry that must ripple from the least-significant word upward. Negating each half with its own `+1` would add one twice and give the wrong result.

The two negate modes solve this by making the `+1` explicit and routable:

- The **low** (least-significant) gate uses `GATE_NEG`. It performs the real `~x + 1` and exposes the resulting carry on its `carry_o`.
- The **high** (more-significant) gate uses `GATE_NEG_CARRY`. Instead of its own `+1`, it adds the low gate's carry via `carry_i`.

Wiring the low gate's `carry_o` into the high gate's `carry_i` makes the `+1` ripple exactly once, from the bottom of the operand to the top, so the concatenation of the two gates' `out_o` is the exact two's-complement negation of the whole wide operand. The negation still keeps `WIDTH` bits per word, so the combined operand's most-negative value wraps, as it should. See [gate_a_n](gate_a_n.md) for the sibling operand-A path, which needs only zeroing and so has no carry ports.

Source: [gate_b_n.sv](../../rtl/gate_b_n.sv)
