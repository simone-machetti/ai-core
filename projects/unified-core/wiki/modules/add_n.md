# Adder N

`add_n` — Parameterized two-input adder with a carry chain: `{cout_o, out_o} = in_0_i + in_1_i + cin_i`.

## Purpose

Adds two `(WIDTH + CARRY)`-bit carry-save rows and a `CARRY`-bit carry-in, and presents the result split into a `WIDTH`-bit sum `out_o` (the low bits, e.g. the word going to a register) and a `CARRY`-bit carry-out `cout_o` (the top bits). Exporting the carry separately lets adjacent lanes chain into a wider result — the low lane's `cout_o` feeds the high lane's `cin_i` — without ever widening the stored word past `WIDTH`. `CARRY` is normally `1`, but is wider where a single window folds more than two rows and its overflow needs more than one bit — [acc_array](./acc_array.md) folds three 20-bit rows per window (through a 22-bit CPR), whose carry into the next lane is 2 bits, so it instantiates `add_n` with `WIDTH = 20`, `CARRY = 2`.

## Parameters

| Parameter | Default | Description                                              |
| --------- | ------- | -------------------------------------------------------- |
| `WIDTH`   | 8       | Bit width of the sum output.                             |
| `CARRY`   | 1       | Carry width; the operands are `WIDTH + CARRY` bits wide. |

## Interface

| Signal   | Dir | Width         | Description                                                    |
| -------- | --- | ------------- | -------------------------------------------------------------- |
| `in_0_i` | in  | `WIDTH+CARRY` | First operand row.                                             |
| `in_1_i` | in  | `WIDTH+CARRY` | Second operand row.                                            |
| `cin_i`  | in  | `CARRY`       | Carry-in (from the lower lane, or `0` for a standalone adder). |
| `out_o`  | out | `WIDTH`       | Low `WIDTH` bits of `in_0_i + in_1_i + cin_i`.                 |
| `cout_o` | out | `CARRY`       | Top `CARRY` bits (the carry-out), for the next lane.           |

## Instantiation

```systemverilog
add_n #(
    .WIDTH (20),
    .CARRY (2)
) add_n_i (
    .in_0_i (a),
    .in_1_i (b),
    .cin_i  (carry_in),
    .out_o  (sum),
    .cout_o (carry_out)
);
```

## Internal logic

The module is purely combinational — a single `(WIDTH + CARRY)`-bit addition whose result is split into the sum and the carry-out:

```systemverilog
assign {cout_o, out_o} = in_0_i + in_1_i + (WIDTH+CARRY)'(cin_i);
```

The two `(WIDTH + CARRY)`-bit rows and the carry-in are summed at `WIDTH + CARRY` bits, and the concatenation `{cout_o, out_o}` splits that result: the low `WIDTH` bits go to `out_o` (the register word), the top `CARRY` bits to `cout_o` (the carry into the next window). This works whenever the resolved value fits in `WIDTH + CARRY` bits — the intended use, e.g. `acc_array`'s three-row window fold, whose value is at most `3·(2^20 − 1) < 2^22` and so fits the 22-bit `{cout_o, out_o}`.

There is no signedness control. `add_n` treats its inputs as unsigned; when it resolves a signed value, the sign is carried by upstream sign-extension (in [acc_array](./acc_array.md) each tap is sign-extended to 40 bits and windowed before the lane adds), so the plain unsigned add with the carry chain reconstructs the correct signed result across the fused lanes.

Source: [add_n.sv](../../rtl/add_n.sv)
