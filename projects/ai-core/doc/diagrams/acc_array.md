# acc_array

Companion description for [`acc_array.excalidraw`](acc_array.excalidraw). The 8-lane accumulator — the final PE stage.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

## Purpose

Eight accumulation lanes, one per output. Each lane selects a `pe_array` tap level, compresses the new carry-save partial into the running accumulator, resolves it to a binary value, optionally chains its carry to an adjacent lane (to fuse two 20-bit lanes into a 40-bit result), and drives an output.

## Interface

| Signal           | Dir | Width   | Description                                                          |
| ---------------- | --- | ------- | -------------------------------------------------------------------- |
| `clk_i`          | in  | 1       | Clock.                                                               |
| `rst_ni`         | in  | 1       | Async active-low reset.                                              |
| `l0_*_i[0:7]`    | in  | 18 each | L0 tap pairs (`sum`, `carry`), from `pe_array`.                      |
| `l1_*_i[0:3]`    | in  | 29 each | L1 tap pairs.                                                        |
| `l2_*_i[0:1]`    | in  | 37 each | L2 tap pairs.                                                        |
| `l3_*_i`         | in  | 38      | L3 tap pair.                                                         |
| `acc_i[0:7]`     | in  | 20 each | External accumulator word, one per lane.                             |
| `sel_out_i[1:0]` | in  | 2       | Tap-level select — which tree level (L0/L1/L2/L3) all lanes read.    |
| `sel_acc_i`      | in  | 1       | Accumulate MUX: `0` = fold `acc_i[k]`, `1` = fold register feedback. |
| `prop_carry_i`   | in  | 1       | Inter-lane carry-chain enable (lane fusion).                         |
| `pe_out_o[0:7]`  | out | 20 each | Per-lane results (figure `PE_OUT`).                                  |

`sel_out_i`, `sel_acc_i`, `prop_carry_i` are **shared** across all lanes (single signals, not per-lane vectors). `sel_out_i` and `prop_carry_i` are mode-derived (decoded by `pe_ctrl`); `sel_acc_i` is a per-cycle control choosing the external accumulator word versus internal feedback.

## Internal structure

Counts from the figure: **16 `MUX`** (2 per lane: tap-level select + accumulate select), **8 `CPR 3:2`**, **8 `ADD`**, **8 `REG`**, **4 carry `&`** gates (fuse lane pairs `(0,1) (2,3) (4,5) (6,7)`).

Per lane:
```
 taps ──[MUX]── (sel_out: tap-level select, over 40-bit sum+carry windows)
            │   ┌─ acc_i[k] or REG feedback ──[MUX] (sel_acc)
            ▼   ▼
         [CPR 3:2]      ← fold {tap_sum, tap_carry, acc} into two rows (EXT=2, 22-bit)
            │
          [ADD] &       ← resolve to 20-bit window + 2-bit carry; & chains carry to next lane
            │
          [REG]         ← accumulator register (feedback + output)
            │
          pe_out_o[k]
```

A wide tap is sign-extended to 40 bits and split into 20-bit halves: the **H** half `[39:20]` feeds the even lane of a pair, the **L** half `[19:0]` the odd lane. `prop_carry_i` then chains the 2-bit carry `L(odd) → gate_n → H(even)` so the pair acts as one 40-bit accumulator. Signedness is handled by that 40-bit sign-extension, so the `CPR`/`ADD` run unsigned.

## Tap → lane wiring (from the figure)

| Lane | Available taps                        |
| ---- | ------------------------------------- |
| 0    | `l0[0]`, `l1[0]H`                     |
| 1    | `l0[1]`, `l1[0]L`                     |
| 2    | `l0[2]`, `l1[1]H`, `l2[0]H`           |
| 3    | `l0[3]`, `l1[1]L`, `l2[0]L`           |
| 4    | `l0[4]`, `l1[2]H`                     |
| 5    | `l0[5]`, `l1[2]L`                     |
| 6    | `l0[6]`, `l1[3]H`, `l2[1]H`, `l3[0]H` |
| 7    | `l0[7]`, `l1[3]L`, `l2[1]L`, `l3[0]L` |

Lanes 6/7 reach `l3` (the single fully-reduced output) and so back the deepest 40-bit modes.

## High-level behavior

1. **Tap select** — the shared `sel_out_i` picks one tap level for the whole array; each lane routes its own node at that level (Mode 1 → all lanes take `l0`; Mode 8 → the single result lands on `l3` across lanes 6/7). Lanes with no node at the selected level are unused for that mode.
2. **Accumulate** — the CPR always folds a third row chosen by `sel_acc_i`: the external word `acc_i[k]` (`0`) or the lane's register feedback (`1`). A plain resolved output is `acc_i = 0` with `sel_acc = 0`; an externally-seeded or running accumulation uses the two modes together.
3. **Resolve + fuse** — `ADD` turns the carry-save fold into a 20-bit window plus a 2-bit carry; `prop_carry_i` chains that carry between paired lanes to build 40-bit results from two 20-bit lanes.
4. **Output** — each lane's register drives `pe_out_o[k]`; a fused result is the concatenation `{pe_out[even], pe_out[odd]}` (H then L).

## Notes

- The 3-row window fold overflows bit 19 by up to 2 bits, so the `CPR 3:2` keeps two guard bits (`EXT = 2`, 22-bit rows) and the inter-lane carry is 2 bits — see [acc_array](../../wiki/architecture/acc_array.md) and [`add_n`](../../rtl/add_n.sv).
- Verified end to end (`disp_array → pe_array → acc_array`) across all 11 modes, single-shot and accumulating.
