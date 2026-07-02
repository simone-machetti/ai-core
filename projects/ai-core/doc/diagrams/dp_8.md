# dp_8

Companion description for [`dp_8.excalidraw`](dp_8.excalidraw). The `DP8 (8×4)` dot-product core —
one lane of the `pe_array` (instanced ×16). Phase-A interface check.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

> **Figure is behind the RTL.** The drawing shows the earlier signed-only path — 2 partial-product
> weights (`CPR 8:2` ×2, one `<< 2`, `CPR 4:2`), signed `b`, 16-bit output. The implemented
> [`dp_8`](../../rtl/dp_8.sv) adds **per-operand signedness**: an unsigned `b` needs a **third** Booth
> partial product, so it has `CPR 8:2` ×3, shifts `<< 2` **and** `<< 4`, a `CPR 6:2`, and a **17-bit**
> output. Text below describes the implemented block; redraw the figure to match.

## Purpose

Compute the length-8 dot product `Σ_{k=0..7} a_k · b_k` of eight `int8 × int4` products and return it
in **carry-save** form (`sum_o`, `carry_o`), leaving the carry-propagate resolve to the downstream
`pe_array` tree / `acc_array`. Implemented by [`dp_8`](../../rtl/dp_8.sv) — fixed to this size, with
every width at its minimum.

## Interface

| Signal          | Dir | Width  | Description                                                       |
| --------------- | --- | ------ | ---------------------------------------------------------------- |
| `a_i[0:7]`      | in  | 8 each | Multiplicand elements (`int8`), one per lane.                    |
| `b_i[0:7]`      | in  | 4 each | Multiplier elements (`int4`), radix-4 Booth-recoded, one per lane.|
| `is_signed_a_i` | in  | 1      | Multiplicand signedness: `1` = signed, `0` = unsigned (control). |
| `is_signed_b_i` | in  | 1      | Multiplier signedness: `1` = signed, `0` = unsigned (control).   |
| `sum_o`         | out | 17     | Sum row of the carry-save result.                                |
| `carry_o`       | out | 17     | Carry row; `sum_o + carry_o = Σ aₖ·bₖ` (mod `2^17`).             |

`a` and `b` are signed/unsigned **independently** (per the operating modes: a field's high half is
signed, its low half unsigned). The dot product spans a 16-bit signed range `[−16320, +30600]` (the
`u×u` corner `8·255·15` and the `u×s` corner `8·255·(−8)`); the final 6:2 compressor produces 18-bit
rows (set by the weight-`2^4` aligned rows), but that leaves two guard bits, so the redundant top bit
is dropped and the output is **17 bits** (16-bit value + 1 guard). See [`dp_8`](../../rtl/dp_8.sv) for
the per-stage width breakdown.

## Internal structure

Implemented counts: **8 `Booth Radix-4`** (one per lane, `PP_SIZE = 3`), **3 `CPR 8:2`** (one per
radix-4 weight), **2 shifters** (`<< 2`, `<< 4`), **1 `CPR 6:2`** (final reduce).

```
   a_i[k], b_i[k]   (k = 0..7)
        │
   Booth Radix-4 [0..7]     each lane → 3 partial products (weights 2^0, 2^2, 2^4)
    │    │    │
 (w0)  (w1)  (w2)
 CPR8:2 CPR8:2 CPR8:2       8 same-weight PPs → 2 rows each
   │      │      │
   │    << 2   << 4         radix-4 weight alignment
   └──────┼──────┘
       CPR 6:2               6 rows (2+2+2) → 2 rows
          │
      sum_o, carry_o
```

## High-level behavior

- **Multiply:** each `Booth Radix-4 [k]` recodes `b_i[k]` and generates `PP_SIZE = 3` partial products
  of `a_i[k] · b_i[k]` (weights `2^0`, `2^2`, `2^4`). The weight-`2^4` product is `0` for a signed `b`
  and the extra `{0, +a}` term for an unsigned `b`.
- **Per-weight reduce:** for each of the three weights, one `CPR 8:2` sums the eight same-weight
  partial products across the lanes into a carry-save pair.
- **Align:** the weight-`2^2` and weight-`2^4` pairs are left-shifted `<< 2` / `<< 4` to line up.
- **Final reduce:** a `CPR 6:2` merges the six rows into the two carry-save outputs `sum_o` / `carry_o`.
- Purely combinational — no clock, no storage. The partial products are always signed, so the
  compressors run signed; `is_signed_a_i` / `is_signed_b_i` set only the operand extensions.

## Open items

- The `.excalidraw` figure still shows the signed-only 2-weight path — redraw it for the 3-weight,
  per-operand-signedness block described above.
