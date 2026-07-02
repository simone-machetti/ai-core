# disp_array

Companion description for [`disp_array.excalidraw`](disp_array.excalidraw). The operand-dispatch IP —
implemented by [`disp_array.sv`](../../rtl/disp_array.sv) and built from the primitive library.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

## Purpose

Route the two 256-bit operands into the 16 per-DP8 operands using **one 4→1 MUX per operand per pair**
(no crossbar) plus a fixed B high/low split and per-DP8 B gating. Each `2×DP8` pair reads exactly one
64-bit A block and one 64-bit B block. Data-path only: the per-DP8 signedness (`is_signed_a`/
`is_signed_b`) comes from `pe_ctrl`, it is not routed here.

## Interface

| Signal          | Dir | Width   | Description                                                  |
| --------------- | --- | ------- | ------------------------------------------------------------ |
| `clk_i`         | in  | 1       | Clock.                                                       |
| `rst_ni`        | in  | 1       | Async active-low reset.                                      |
| `pe_in_a_i`     | in  | 256     | Operand A (4 × 64-bit blocks).                               |
| `pe_in_b_i`     | in  | 256     | Operand B (4 × 64-bit blocks).                               |
| `sel_a_i[0:7]`  | in  | 2 each  | Per-pair A-block select (4→1).                               |
| `sel_b_i[0:7]`  | in  | 2 each  | Per-pair B-block select (4→1).                               |
| `ctr_l_i[0:7]`  | in  | 2 each  | Even-DP8 B gate: `0` pass, `1` zero, `2` negate.             |
| `ctr_h_i[0:7]`  | in  | 2 each  | Odd-DP8 B gate: `0` pass, `1` zero, `2` negate.              |
| `a_dp8_o[0:15]` | out | 64 each | A operand per DP8 (8 × int8).                                |
| `b_dp8_o[0:15]` | out | 32 each | B operand per DP8 (8 × int4).                                |

## Internal structure

Input registers latch the two operands (4 × 64-bit A blocks + 4 × 64-bit B blocks). Then 8 pairs, per
pair: **1 MUX A** (4→1, 64b, shared by both DP8s), **1 MUX B** (4→1, 64b) split low/high 32, and
**2 `gate_b_n`** (per-int4 pass/zero/negate) on the two B halves. **No A gate** — a lane is idled by
zeroing its B.

Counts: 2 `REG` banks (4 + 4 × 64b), 16 `MUX` (8 A + 8 B), 16 `gate_b_n` (2 per pair).

```
 pe_in_a_i(4×64)  pe_in_b_i(4×64)
        │               │
   REG(4×64)        REG(4×64)                       ← input registers
        │               │
   per pair p (0..7):
   MUX A(4→1) sel_a[p] ─→ a_dp8_o[2p] = a_dp8_o[2p+1]     (shared A block)
   MUX B(4→1) sel_b[p] ─→ low32 → gate_b_n(ctr_l) → b_dp8_o[2p]
                          high32 → gate_b_n(ctr_h) → b_dp8_o[2p+1]
```

## High-level behavior

For each pair `p` (0..7): `mux_a` selects one A block, feeding both DP8s of the pair; `mux_b` selects
one B block, its low 32 bits going to the even DP8 (`2p`) and high 32 to the odd DP8 (`2p+1`); each B
half passes through a `gate_b_n` that per int4 element passes, zeros (idle lane), or two's-complement-
negates (complex-mode imaginary term). The dispatch is combinational after the input registers. The
per-mode `sel_*`/`ctr_*` vectors are the `modes.xlsx` dispatch map (the reference for `pe_ctrl`).

## Notes (Phase-A items now resolved)

- **B-gate only** (no A gate): zeroing B idles a lane (`a·0 = 0`); negation is only ever on B. The
  figure's earlier "24 gates" / A-zero were Phase-A guesses — the build uses 16 `gate_b_n`, B-only.
- **H/L split**: low 32 → even DP8 (`2p`), high 32 → odd DP8 (`2p+1`).
- **Signedness** is a `pe_ctrl`→DP8 control, not routed through here.
- **Registers** sit on the input (matches the figure).
