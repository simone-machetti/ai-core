# pe_array

Companion description for [`pe_array.excalidraw`](pe_array.excalidraw). The 16-DP8 reduction tree.
Phase-A interface check.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

## Purpose

Compute the **16 `dp8_8x4` partial products** and reduce them through a 4-level carry-save tree
with programmable per-level shifts, exposing a tap at **every** level so a mode can read its
results at the depth matching its parallelism (8 results → L0 … 1 result → L3).

## Interface

| Signal             | Dir | Width     | Description                                                                |
| ------------------ | --- | --------- | -------------------------------------------------------------------------- |
| `clk_i`            | in  | 1         | Clock.                                                                     |
| `rst_ni`           | in  | 1         | Async active-low reset.                                                    |
| `a_dp8_i[0:15]`    | in  | 64 each   | A operand per DP8 (8 × int8).                                              |
| `b_dp8_i[0:15]`    | in  | 32 each   | B operand per DP8 (8 × int4).                                              |
| `sel_shift_i[2:0]` | in  | 1 each    | Shift-stage selects: `[0]`=L0 `<<8/0`, `[1]`=L1 `<<4/0`, `[2]`=L2 `<<8/0`. |
| `l0_o[0:7]`        | out | tap       | Level-0 taps (least reduced).                                              |
| `l1_o[0:3]`        | out | tap (H/L) | Level-1 taps.                                                              |
| `l2_o[0:1]`        | out | tap (H/L) | Level-2 taps.                                                              |
| `l3_o[0]`          | out | tap (H/L) | Level-3 tap (fully reduced).                                               |

Tap form is **carry-save** (sum + carry); wide nodes are exposed as H/L 20-bit halves so two
adjacent `acc_array` lanes can fuse them. Exact tap widths fixed once `dp8_8x4` sets the number form.

## Internal structure

Counts from the figure: 16 `DP8`, **15 `CPR 4:2`** (8+4+2+1), **14 shifters**
(10 `<<8/0` = 8 at L0-in + 2 at L2-in; 4 `<<4/0` at L1-in), **8 `REG`** (L0 only).

```
 16× dp8_8x4
     │     sel_shift[0]:  << 8/0   (×8)
   CPR 4:2 (×8)  ──REG(×8)──▶  l0[0:7]
     │     sel_shift[1]:  << 4/0   (×4)
   CPR 4:2 (×4)  ───────────▶  l1[0:3]
     │     sel_shift[2]:  << 8/0   (×2)
   CPR 4:2 (×2)  ───────────▶  l2[0:1]
   CPR 4:2 (×1)  ───────────▶  l3[0]
```

## High-level behavior

- Each `dp8_8x4[i]` computes `Σ_{k=0..7} a_k·b_k` in carry-save form.
- **L0 (registered):** `sel_shift_i[0]` optionally left-shifts by 8; a `CPR 4:2` then sums a
  **crossed** DP8 pair — `l0[2g] = dp8[4g]+dp8[4g+2]`, `l0[2g+1] = dp8[4g+1]+dp8[4g+3]` — and
  the result is registered. (Crossover lets an 8-output mode read clean results at L0.)
- **L1/L2/L3 (combinational, straight binary):** `l1[j]=l0[2j]+l0[2j+1]`, `l2[k]=l1[2k]+l1[2k+1]`,
  `l3=l2[0]+l2[1]`. `sel_shift_i[1]`/`[2]` apply the `2^4`/`2^8` weighting before the L1/L2 compress.
- Every level is a **4:2 compressor**: it merges *two* carry-save operands (4 vectors) into one
  carry-save operand (2 vectors). This is the structural evidence that the datapath is carry-save.
- The shift stages realize the `2^k` weights from the per-mode decomposition formulas; the
  crossover groups hi-field DP8 into one L0 node and lo-field into its sibling so the level shift
  recombines them correctly.

## Tap selection (which level a mode reads)

| Parallel results | Tap  | Nodes      |
| ---------------- | ---- | ---------- |
| 8                | `l0` | `l0[0..7]` |
| 4                | `l1` | `l1[0..3]` |
| 2                | `l2` | `l2[0..1]` |
| 1                | `l3` | `l3[0]`    |

## Open items

- Exact tap bit-widths (set by the `dp8_8x4` number-form decision).
- Confirm the L0 register is the only pipeline register inside this IP (L1–L3 combinational).
- H/L tap semantics finalized jointly with `acc_array`.
