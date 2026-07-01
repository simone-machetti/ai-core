# pe_top

Companion description for [`pe_top.excalidraw`](pe_top.excalidraw). Top-level of one
Processing Element (PE). Written as part of the Phase-A interface check.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase signal names
> with `_i`/`_o` suffixes (`_n` = active-low). Figure label given in parentheses where useful.

## Purpose

One PE is a reconfigurable fixed-point MatMul engine built from **16 × `dp8_8x4`**
(128 8b×4b multipliers). It evaluates one of the 11 operating modes (1–3, 5–12) selected by
`mode_i`. The full chip tiles this PE **8×8** (see [`pe_matrix.md`](pe_matrix.md)).

**Caller contract:** drive `pe_in_a_i`, `pe_in_b_i`, `mode_i`, and `sel_acc_i` (direct output vs
accumulate) → read `pe_out_o`. Everything else (`sel_a`/`sel_b`, `ctr_l`/`ctr_h`, `sel_shift`,
`sel_tap`, `prop_carry`, `sel_out`) is derived internally from `mode_i` by `pe_ctrl`.

## External interface

| Signal                   | Dir | Width   | Description                                                                                     |
| ------------------------ | --- | ------- | ----------------------------------------------------------------------------------------------- |
| `clk_i`                  | in  | 1       | Clock. *(Not drawn in the figure; required by the REG stages.)*                                 |
| `rst_ni`                 | in  | 1       | Asynchronous active-low reset. *(Not drawn; required by the REGs.)*                             |
| `pe_in_a_i` (PE_IN_A)    | in  | 256     | Operand A — 4 × 64-bit blocks, each block = 8 × int8 `a` values.                                |
| `pe_in_b_i` (PE_IN_B)    | in  | 256     | Operand B — 4 × 64-bit blocks, each block = two 32-bit B operands (8 × int4 each).              |
| `mode_i` (MODE)          | in  | 4       | Operating-mode select (decoded by `pe_ctrl`).                                                   |
| `sel_acc_i` (SEL_ACC)    | in  | 1       | Accumulate (1) vs normal output (0). Shared across all 8 lanes; per-cycle control.              |
| `pe_out_o[0:7]` (PE_OUT) | out | 20 each | Per-lane results. 40-bit modes occupy **two fused lanes** (see [`acc_array.md`](acc_array.md)). |

`ACC[0:7]` in the figure is the `acc_array` accumulator-register bus that drives `pe_out_o`
(post `sel_out`). All `sel_*` / `ctr_*` are **internal** — produced by `pe_ctrl` from `mode_i` —
**except `sel_acc_i`, which is a top-level input** (like `mode_i`): a single shared bit choosing,
each cycle, whether the lanes accumulate onto their running sum or emit a fresh result. No separate
accumulate/clear/valid handshake is needed.

## Internal structure

Four sub-IPs. Datapath flows left→right; `pe_ctrl` fans the internal control to all three datapath
IPs, while `sel_acc_i` reaches `acc_array` directly from the top level.

```
  mode_i ─▶ pe_ctrl ─── sel_a/sel_b, ctr_l/ctr_h, sel_shift, sel_tap, prop_carry, sel_out
                            (internal control fan-out)
  pe_in_a_i ┐
  pe_in_b_i ┤
       disp_array ──a_dp8[0:15],b_dp8[0:15]──▶ pe_array ──l0/l1/l2/l3──▶ acc_array ──▶ pe_out_o[0:7]
                                                                            ▲
                                                            sel_acc_i (external, per-cycle)
```

| Sub-IP       | Doc                            | Role                                                                                              |
| ------------ | ------------------------------ | ------------------------------------------------------------------------------------------------- |
| `disp_array` | [disp_array.md](disp_array.md) | Route the 256-bit A/B into the 16 `(a_dp8, b_dp8)` operands.                                      |
| `pe_array`   | [pe_array.md](pe_array.md)     | 16 `dp8_8x4` + 4-level shift/compress reduction tree; taps `l0`–`l3`.                             |
| `acc_array`  | [acc_array.md](acc_array.md)   | Per-lane tap select, carry-save resolve, lane fusion, accumulate, output.                         |
| `pe_ctrl`    | *(no diagram)*                 | Combinational decode `mode_i` → all selects. Built **last** (contract known once 1–4 are pinned). |

## Internal signal contract

| Bus                                   | Producer → Consumer | Shape              | Meaning                                                  |
| ------------------------------------- | ------------------- | ------------------ | -------------------------------------------------------- |
| `a_dp8[0:15]`                         | disp → pe_array     | 64b each           | A operand per DP8 (shared within a pair).                |
| `b_dp8[0:15]`                         | disp → pe_array     | 32b each           | B operand per DP8 (after H/L split + zero/negate).       |
| `l0[0:7]`,`l1[0:3]`,`l2[0:1]`,`l3[0]` | pe_array → acc      | carry-save taps    | Wide nodes split H/L into 20-bit halves for lane fusion. |
| `sel_a[0:7]`,`sel_b[0:7]`             | ctrl → disp         | 2b each            | Per-pair 4→1 block select.                               |
| `ctr_l[7:0]`,`ctr_h[3:0]`             | ctrl → disp         | 1b each            | Zero / sign-negate gate controls.                        |
| `sel_shift[2:0]`                      | ctrl → pe_array     | 1b each            | Tree shift-stage selects.                                |
| `sel_tap`,`prop_carry`,`sel_out[1:0]` | ctrl → acc          | shared (all lanes) | Tap-level select / lane fusion / output format.          |

`sel_acc_i` is **not** in this table: it is a top-level input (see External interface) routed
unchanged to all `acc_array` lanes, not produced by `pe_ctrl`. (`sel_tap` is a working name for the
mode-derived tap-level select — see [`acc_array.md`](acc_array.md).)

## High-level behavior

1. `pe_ctrl` decodes `mode_i` into every `sel_*`/`ctr_*` (pure function of `mode_i`; the per-mode
   values are the workbook `Modes`-sheet Dispatch/Shifter rows).
2. `disp_array` selects, per pair, one 64-bit A block and one 64-bit B block, applies the fixed
   B hi/lo split and the zero/negate gates, and emits `a_dp8[0:15]` (64b) / `b_dp8[0:15]` (32b).
3. `pe_array` computes 16 `dp8_8x4` partials and reduces them through 3 programmable shift stages
   + 4:2 compressors, exposing taps at every level (L0 = 8 nodes … L3 = 1 node).
4. `acc_array` selects one shared tap level (= number of parallel results), resolves the
   carry-save form, fuses adjacent lanes for wide (40-bit) outputs, optionally accumulates over
   cycles (under the external `sel_acc_i`), and drives `pe_out_o[0:7]`.

## Pipeline

Registered at three points: `disp_array` (8 REG), `pe_array` L0 (8 REG), `acc_array` (8 REG) →
≈3-stage pipeline. Exact retiming/latency to be confirmed during integration.

## Open items

- `clk_i`/`rst_ni` absent from the figure — to be added.
- Datapath number form (carry-save vs resolved) — settled at the `dp8_8x4` check; the 4:2/3:2
  compressors strongly imply **carry-save** through the tree, resolved in `acc_array`.
- Whether the accumulator bus (`ACC[0:7]`) is separately exposed at the top level or only `pe_out_o[0:7]`.
- Final name/width of the internal tap-level select (`sel_tap` working name).
