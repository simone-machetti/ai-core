# acc_array

Companion description for [`acc_array.excalidraw`](acc_array.excalidraw). The 8-lane accumulator.
Phase-A interface check.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

## Purpose

Eight accumulation lanes, one per output. Each lane selects a tree tap, compresses the new
partial into a running carry-save accumulator, resolves it to a binary sum, optionally chains
carries to an adjacent lane (to fuse two 20-bit lanes into a 40-bit result), and drives an output.

## Interface

| Signal           | Dir | Width     | Description                                                                                                    |
| ---------------- | --- | --------- | -------------------------------------------------------------------------------------------------------------- |
| `clk_i`          | in  | 1         | Clock.                                                                                                         |
| `rst_ni`         | in  | 1         | Async active-low reset.                                                                                        |
| `l0_i[0:7]`      | in  | tap       | Level-0 taps.                                                                                                  |
| `l1_i[0:3]`      | in  | tap (H/L) | Level-1 taps.                                                                                                  |
| `l2_i[0:1]`      | in  | tap (H/L) | Level-2 taps.                                                                                                  |
| `l3_i[0]`        | in  | tap (H/L) | Level-3 tap.                                                                                                   |
| `sel_tap_i`      | in  | 2         | Tap-**level** select (which tree level all lanes read); internal, from `pe_ctrl`. *(Working name — see note.)* |
| `sel_acc_i`      | in  | 1         | **External** input (like `mode_i`): accumulate (1) vs normal output (0). Shared by all lanes.                  |
| `prop_carry_i`   | in  | 1         | Inter-lane carry-chain enable (lane fusion); shared.                                                           |
| `sel_out_i[1:0]` | in  | 2         | Output format / which lanes drive `pe_out_o`; shared.                                                          |
| `pe_out_o[0:7]`  | out | 20 each   | Per-lane results (figure `PE_OUT`; accumulator bus is `ACC`).                                                  |

All four control signals are **shared** across the 8 lanes (single signals, not per-lane vectors).
`sel_tap_i`, `prop_carry_i`, `sel_out_i` are **mode-derived** (decoded by `pe_ctrl`); `sel_acc_i`
is a **top-level input** chosen per cycle — it picks accumulation vs normal output and so is the
per-cycle accumulate control.

> **Note on `sel_tap_i`:** the figure's single `SEL_ACC` label is now assigned to the 1-bit
> accumulate select `sel_acc_i`. The per-lane *tap-level* MUX still needs a control, so it is given
> the working name `sel_tap_i` here (internal, mode-derived). Final name/width TBD.

## Internal structure

Counts from the figure: **16 `MUX`** (2 per lane: tap-level select + accumulate select), **8 `CPR 3:2`**,
**8 `ADD`**, **8 `REG`**, **4 carry `&`** gates (fuse lane pairs `(0,1) (2,3) (4,5) (6,7)`).

Per lane:
```
 taps ──[MUX]── (sel_tap: tap-level select)
            │   ┌─ accumulator feedback (REG) or 0 ──[MUX] (sel_acc: accumulate / normal)
            ▼   ▼
         [CPR 3:2]      ← fold new partial (sum+carry) into running accumulator
            │
          [ADD] &       ← resolve carry-save; & chains carry to next lane (prop_carry)
            │
          [REG]         ← accumulator register
            │
        (sel_out) ──▶ pe_out_o[k]
```

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

A wide node feeds its **H** half to the even lane and **L** half to the odd lane of a pair;
`prop_carry_i` then chains the carry so the pair acts as one 40-bit accumulator. Lanes 6/7 reach
`l3` (the single fully-reduced output) and so back the deepest 40-bit modes.

## High-level behavior

1. **Tap select** — the shared `sel_tap_i` picks one **tap level** for the whole array; each lane
   then routes its own node at that level (Mode 1 → all lanes take `l0`; Mode 8 → the single result
   lands on `l3`). Lanes with no node at the selected level are unused for that mode.
2. **Accumulate vs normal** — the external `sel_acc_i` (1 bit, shared) chooses, each cycle, whether
   the lane folds the running accumulator (REG feedback) back in via `CPR 3:2` (**accumulate**) or
   emits the new partial alone (**normal output**). The MUX has exactly two inputs, hence one bit.
3. **Resolve + fuse** — `ADD` turns carry-save into a binary sum; the shared `prop_carry_i` chains
   the carry between paired lanes to build 40-bit results from two 20-bit lanes.
4. **Output** — the shared `sel_out_i` formats / selects which lane registers drive `pe_out_o[0:7]`.

## Open items

- Confirm the tap-level select signal (`sel_tap_i` working name): final name, width, and whether it
  is shared (one level for all lanes) or per-lane.
- Whether one shared `prop_carry_i` enable suffices for every mode's fusion pattern (the lane-pair
  boundaries `(0,1) (2,3) (4,5) (6,7)` fuse together).
- The `sel_acc_i` "normal output" MUX input: confirm it is `0` (so `CPR 3:2` passes the new partial
  through) vs a full accumulate bypass.
