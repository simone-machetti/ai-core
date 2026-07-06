---
type: module
title: Register N
description: Parameterized register bank — SIZE independent WIDTH-bit registers with a shared async active-low reset.
resource: rtl/reg_n.sv
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
| -------- | --- | ---------------- | --------------------------------------------------------- |
| `clk_i`  | in  | 1                | Clock; registers update on the rising edge.               |
| `rst_ni` | in  | 1                | Asynchronous active-low reset; clears all registers to 0. |
| `d_i`    | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`.                |
| `q_o`    | out | `SIZE` × `WIDTH` | Registered outputs — unpacked array `[0:SIZE-1]`.         |

## Instantiation

```systemverilog
reg_n #(.WIDTH(8), .SIZE(4)) reg_n_i (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .d_i    (d),
    .q_o    (q)
);
```

## Internal logic

The whole bank is one clocked process. There is no combinational output path — `q_o` is state, driven only inside an `always_ff`.

### Sensitivity: clock and asynchronous reset

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
```

The process wakes on two events: the rising edge of `clk_i` (normal operation) and the falling edge of `rst_ni` (reset assertion). Listing `negedge rst_ni` in the sensitivity list is what makes the reset *asynchronous* — the clear happens the moment `rst_ni` drops, without waiting for a clock edge.

### Reset branch: clear the whole bank

```systemverilog
if (!rst_ni) begin
    for (int i = 0; i < SIZE; i++) begin
        q_o[i] <= '0;
    end
end
```

`rst_ni` is active-low, so `!rst_ni` (i.e. `rst_ni == 0`) is the reset condition. While it holds, the `for` loop clears every one of the `SIZE` registers to `'0` — the width-agnostic zero literal fills all `WIDTH` bits of each word. Because the branch is reached asynchronously and stays true as long as `rst_ni` is low, the outputs are held at zero for the entire reset interval regardless of the clock.

### Clocked branch: capture every input word

```systemverilog
end else begin
    for (int i = 0; i < SIZE; i++) begin
        q_o[i] <= d_i[i];
    end
end
```

When `rst_ni` is high, this branch is taken on each rising `clk_i` edge. The loop copies each input word `d_i[i]` into its register `q_o[i]`. There is no enable and no feedback, so every register unconditionally samples its `d_i` on every clock — the bank is a plain set of `SIZE` parallel D flip-flop groups.

### Non-blocking assignment and shared control

All updates use the non-blocking operator `<=`, so every `q_o[i]` samples the *old* values simultaneously at the edge; the registers do not see each other's new values within the same cycle. `WIDTH` sets the width of each register and `SIZE` the number of them; all `SIZE` registers share the single `clk_i` and `rst_ni`, so the bank resets and clocks as one unit.

### Hold and accumulate come from outside

The bank has no load-enable: each register reloads every cycle. Any "keep the current value" or "accumulate" behavior must be built in the logic feeding `d_i` — e.g. muxing `q_o` back into `d_i` to hold, or feeding an adder's sum to accumulate. This keeps the primitive minimal and reusable across the PE's pipeline and accumulator stages.

Source: [reg_n.sv](../../rtl/reg_n.sv)
