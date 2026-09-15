# Complementer N

`comp_n` — a parameterized bitwise complementer over `SIZE` words of `WIDTH` bits. Each word is passed through when `neg_i = 0` or one's-complemented (`~word`) when `neg_i = 1`; the single select is shared by all words. It is the invert sibling of [gate_n](./gate_n.md) (which *zeros*), used in [pe_array_sqr](./pe_array_sqr.md) to relocate the complex-mode block negate onto a carry-save pair.

## Purpose

The square variant drops the complex-mode negate from the B dispatcher (`gate_b_n`'s `GATE_NEG`/`GATE_NEG_CARRY` are gone — see [disp_array_b_sqr](./disp_array_b_sqr.md)) and relocates it into the tree, because under centering a per-operand subtract-and-square no longer negates cleanly. Negating a whole DP8 block is done here by one's-complementing **both** carry-save rows (`~sum`, `~carry`): since `~x = −x − 1`, the pair resolves to `−(sum + carry) − 2 = −S_DP8 − 2`. The tree then carries `−S_DP8 − 1` per row; the leftover `+2` per negated block is data-independent and is folded back downstream as part of `acc_array_sqr`'s per-mode constant `C`. So `comp_n` does the sign flip and defers the two's-complement `+1`-per-row to the accumulator.

## Parameters

| Parameter | Default | Description                          |
| --------- | ------- | ------------------------------------ |
| `WIDTH`   | `8`     | Bit width of each word.              |
| `SIZE`    | `2`     | Number of words (all share `neg_i`). |

## Interface

| Signal            | Dir | Width        | Description                                  |
| ----------------- | --- | ------------ | -------------------------------------------- |
| `in_i[0:SIZE-1]`  | in  | `WIDTH` each | Input words.                                 |
| `neg_i`           | in  | 1            | Shared select: `1` = complement, `0` = pass. |
| `out_o[0:SIZE-1]` | out | `WIDTH` each | `neg_i ? ~in_i : in_i`, per word.            |

## Instantiation

In [pe_array_sqr](./pe_array_sqr.md), one instance per L0 node 0–5 sits on the node's **lo** (`CX1`) carry-save pair, before the `ext_n`, with `WIDTH = DP8_WIDTH = 18`, `SIZE = 2`:

```systemverilog
comp_n #(.WIDTH(DP8_WIDTH), .SIZE(2)) comp_n_i (
    .in_i(lo_raw), .neg_i(neg_i[n]), .out_o(lo_in)
);
```

## Internal logic

One conditional-invert per word, all sharing `neg_i`:

```systemverilog
for (i = 0; i < SIZE; i++) begin : gen_comp
    assign out_o[i] = neg_i ? ~in_i[i] : in_i[i];
end
```

Source: [comp_n.sv](../../rtl/comp_n.sv) — used by [pe_array_sqr](./pe_array_sqr.md)
