# Constant LUT (Square)

`const_sqr` — a small combinational LUT addressed by the 4-bit mode, holding the per-mode constant `C` for the square reconstruction `out = ½(PE − α − β + C)`. Because the square accumulator is **fully additive** (it never subtracts), every one of its deferred-constant corrections is folded into this one `C`.

## Purpose

The square accumulator adds four carry-save terms — `PE`, `−α`, `−β`, and `C` — then halves. Two of those terms carry data-independent `comp_n`-style deferrals, and `C` absorbs them so the datapath needs no subtractor and no carry-in injection:

- **`+C_real`** — the excess-8 **centering** constant (verified per mode; see [square_imp.md](../../doc/formulas/square/square_imp.md) §3). Real modes and the **Im(D)** half of complex modes; `Re(D)`'s `C_real = 0` (the `+re·re` and `−im·im` centering constants cancel).
- **`+4`** — subtracting α and β by one's-complementing their taps defers `−2` each (the [pe_array_alpha_sqr](./pe_array_alpha_sqr.md) / [pe_array_beta_sqr](./pe_array_beta_sqr.md) generators emit `−α`/`−β` as `~tap = −tap−2`) → `+4` on **every** output.
- **`−2N`** — the [comp_n](./comp_n.md) block-negate deferral (modes 10/11), tree-weighted, on the **negated `Re(D)`** outputs only (the negated `im·im` group lands in Re, whose `C_real = 0`). `2N = 34`/`68`.

So the module emits two per-mode constants — one for each output half of the complex modes:

```
c_o     = C_real + 4        (positive: Im(D) and all real-mode outputs)
c_neg_o = 0 + 4 − 2N        (negated Re(D) outputs of complex modes; signed)
```

Both are the **signed value the accumulator adds** — no subtract, no sign convention.

## Constants

| mode | prec   | `c_o` = C_real+4   | `c_neg_o` = 4−2N (Re) |
| ---- | ------ | ------------------ | --------------------- |
| 1    | R8R4   | 1 028              | —                     |
| 2    | R8R8   | 36 868             | —                     |
| 3    | R16R8  | 4 892 676          | —                     |
| 5    | R8R4   | 2 052              | —                     |
| 6    | R8R8   | 73 732             | —                     |
| 7    | R16R8  | 9 785 348          | —                     |
| 8    | R16R16 | 2 595 360 772      | —                     |
| 9    | R16R16 | 1 297 680 388      | —                     |
| 10   | C8C8   | 36 868 (Im)        | −30 (= 4 − 34)        |
| 11   | C8C8   | 73 732 (Im)        | −64 (= 4 − 68)        |
| 12   | C16C16 | 1 297 680 388 (Im) | +4 (= 4 − 0)          |

Invalid mode addresses return 0 on both outputs.

## Interface

| Signal    | Dir | Width | Description                                                              |
| --------- | --- | ----- | ------------------------------------------------------------------------ |
| `mode_i`  | in  | 4     | Mode address.                                                            |
| `c_o`     | out | 32    | Positive constant `C_real + 4` (non-negative), added on Im/real outputs. |
| `c_neg_o` | out | 8     | Signed `4 − 2N`, added on the negated Re outputs.                        |

## Parameters

| Parameter    | Default | Description                                            |
| ------------ | ------- | ------------------------------------------------------ |
| `MODE_WIDTH` | `4`     | Mode address width.                                    |
| `C_WIDTH`    | `32`    | Positive-constant width (holds the widest `C_real+4`). |
| `CNEG_WIDTH` | `8`     | Signed Re-constant width (holds `−64 … +4`).           |

## Notes

- The `2N` values (34/68) are the tree-weighted `comp_n` deferrals derived in [square_imp.md](../../doc/formulas/square/square_imp.md) §4. Mode 12 is software pre-negated (no `comp_n`, `N = 0`), so its Re constant is the bare `+4`.
- Consumer: `acc_array_sqr` (a later gate) — it adds `c_o` on the positive/Im outputs and `c_neg_o` on the negated Re outputs, then `÷2`.

Source: [const_sqr.sv](../../rtl/const_sqr.sv)
