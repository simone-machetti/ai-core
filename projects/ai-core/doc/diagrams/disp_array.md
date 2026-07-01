# disp_array

Companion description for [`disp_array.excalidraw`](disp_array.excalidraw). Operand-dispatch IP.
Phase-A interface check.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

## Purpose

Route the two 256-bit operands into the **16 per-DP8 operands** the array needs, using only
**one 4→1 MUX per operand per pair** plus a fixed B split and a few gate cells — no operand
crossbar (per spec §3.5). Implements the per-pair single-block rule: each `2×DP8` pair reads
**exactly one** 64-bit A block and **one** 64-bit B block.

## Interface

| Signal          | Dir | Width   | Description                              |
| --------------- | --- | ------- | ---------------------------------------- |
| `clk_i`         | in  | 1       | Clock.                                   |
| `rst_ni`        | in  | 1       | Async active-low reset.                  |
| `pe_in_a_i`     | in  | 256     | Operand A (4 × 64-bit blocks).           |
| `pe_in_b_i`     | in  | 256     | Operand B (4 × 64-bit blocks).           |
| `sel_a_i[0:7]`  | in  | 2 each  | Per-pair A block select (4→1).           |
| `sel_b_i[0:7]`  | in  | 2 each  | Per-pair B block select (4→1).           |
| `ctr_l_i[7:0]`  | in  | 1 each  | Gate controls (zero/negate), low group.  |
| `ctr_h_i[3:0]`  | in  | 1 each  | Gate controls (zero/negate), high group. |
| `a_dp8_o[0:15]` | out | 64 each | A operand for each DP8 (8 × int8).       |
| `b_dp8_o[0:15]` | out | 32 each | B operand for each DP8 (8 × int4).       |

## Internal structure

8 pairs (one per `2×DP8`). Per pair: **1 MUX A** (4→1), **1 MUX B** (4→1), **1 REG**.
Plus the fixed B hi/lo split (8 `H` + 8 `L` taps) and **24 `&` gate cells**.

Counts from the figure: 8 `MUX A`, 8 `MUX B`, 8 `REG`, 8 `H`, 8 `L`, 24 `&`.

```
 pe_in_a_i(4×64)         pe_in_b_i(4×64)
        │                      │
   [MUX A]·8  (sel_a)     [MUX B]·8  (sel_b)        ← one 4→1 per pair
        │                      │
        │                 split B: lower-32 → even DP8, upper-32 → odd DP8   (H/L fields)
        │                      │
        └──── & gates (zero/negate, ctr_l/ctr_h) ───┘
        │                      │
      [REG]·8 ─────────────────┘
        ▼                      ▼
   a_dp8_o[0:15](64)      b_dp8_o[0:15](32)
```

## High-level behavior

For each pair `p` (0..7):
- **A (shared):** `mux_a` selects one of the four 64-bit A blocks via `sel_a_i[p]`; the result
  feeds **both** DP8 of the pair → `a_dp8_o[2p]` = `a_dp8_o[2p+1]`.
- **B (split):** `mux_b` selects one of the four 64-bit B blocks via `sel_b_i[p]`; a **fixed**
  wiring sends the **lower 32 bits → even DP8** and **upper 32 bits → odd DP8**
  (`b_dp8_o[2p]`, `b_dp8_o[2p+1]`). When B is nibble/byte-split, the two halves are the hi/lo
  fields of that one block.
- **Gates (`&`):** apply the per-DP8 sign-negate (`−bᴵ`, complex modes 10–12) and the
  per-pair A zero-gate (block A → 0, spread Mode 5), controlled by `ctr_l_i`/`ctr_h_i`.
- **Register:** the selected/gated operands are registered (pipeline stage 1).

The 24 `&` gates are consistent with **per-pair A-zero (8) + per-DP8 B-negate (16)**.

## Open items

- Exact mapping of `ctr_l_i[7:0]`/`ctr_h_i[3:0]` (12 controls) onto the 24 gate cells.
- Confirm which physical half (lower/upper 32) corresponds to the `H`/`L` figure labels and to
  even/odd DP8, and the nibble-field routing for byte/nibble-split modes.
- Whether the REG sits before or after the gates (affects timing, not function).
