# Full Adder

`fa` — One-bit full adder: sums three input bits into a sum bit and a carry-out bit.

## Purpose

The 3:2 building block of the carry-save compressors [cpr_c_n](./cpr_c_n.md) and [cpr_w_n](./cpr_w_n.md) — it adds three single-bit inputs and emits their two-bit result as a sum bit (weight 1) and a carry-out bit (weight 2).

## Parameters

None.

## Interface

| Signal   | Dir | Width | Description        |
| -------- | --- | ----- | ------------------ |
| `in_0_i` | in  | 1     | First addend bit.  |
| `in_1_i` | in  | 1     | Second addend bit. |
| `cin_i`  | in  | 1     | Carry-in bit.      |
| `sum_o`  | out | 1     | Sum bit.           |
| `cout_o` | out | 1     | Carry-out bit.     |

## Instantiation

```systemverilog
fa fa_i (
    .in_0_i (a),
    .in_1_i (b),
    .cin_i  (cin),
    .sum_o  (sum),
    .cout_o (cout)
);
```

## Internal logic

The module is purely combinational — no clock, no storage — and consists of two continuous assignments. Numerically it computes the two-bit value `in_0_i + in_1_i + cin_i` (a quantity in the range 0–3) and splits it into the weight-1 output `sum_o` and the weight-2 output `cout_o`, so that at all times `2*cout_o + sum_o == in_0_i + in_1_i + cin_i`.

### Sum bit

```systemverilog
assign sum_o = in_0_i ^ in_1_i ^ cin_i;
```

The sum bit is the exclusive-OR (parity) of the three inputs: it is `1` when an odd number of the three inputs are `1`. This is exactly the least-significant bit of the arithmetic sum `in_0_i + in_1_i + cin_i` — adding 1 flips the LSB, so the LSB tracks the parity of how many ones were added.

### Carry-out bit

```systemverilog
assign cout_o = (in_0_i & in_1_i) | (cin_i & in_0_i) | (cin_i & in_1_i);
```

The carry-out is the *majority* of the three inputs: it is `1` when at least two of them are `1`. That is the weight-2 (upper) bit of the same 0–3 sum, because the running total reaches 2 or more precisely when two or three of the inputs are set. Each AND term detects one pair being both `1`; the OR asserts the carry if any pair qualifies.

Source: [fa.sv](../../rtl/fa.sv)
