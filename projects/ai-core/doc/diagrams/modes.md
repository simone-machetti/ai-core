# modes

Companion description for [`modes.excalidraw`](modes.excalidraw). Mode-decomposition taxonomy.

> **Not a hardware block.** This figure is the *conceptual* map of how each operating mode's large
> dot-product reduces down to the `dp8_8x4` primitive. It documents the basis for `pe_array`'s
> per-mode shifts/weights and `acc_array`'s tap level — there is no `modes` RTL module.

## What the figure shows

A reduction tree whose **leaves are the 16 `DP8(8×4)`** primitives. Each level up is a larger
dot-product realized by recombining DP8 results with power-of-two shifts and compression. The
`#n` annotations are **mode numbers**, placed at the DP-stage that mode targets:

- Leaves: `DP8(8×4)` ×16.
- One level up: `DP16(8×4) #1` and `DP8(16×4)`.
- Higher nodes: `DP16(8×8) #2`, `DP8(16×8) #3`, `DP32(8×4) #5`, `DP32(8×8) #6`,
  `DP16(16×8) #7`, `DP8(16×16) #9`, `DP16(16×16) #8`, etc. — and the complex modes (10–12)
  built from the same real nodes plus the negated-B / re‖im packing.

## Per-mode reduction chains (target op → primitive)

Authoritative source: the `doc/formulas/mode_<n>.tex` (+ `.pdf`) files and the workbook.

| Mode | Precision | Chain                                                       |
| ---: | --------- | ----------------------------------------------------------- |
|    1 | R8R4      | DP16(8×4) → DP8(8×4)                                        |
|    2 | R8R8      | DP16(8×8) → DP16(8×4) → DP8(8×4)                            |
|    3 | R16R8     | DP8(16×8) → DP8(16×4) → DP8(8×4)                            |
|    5 | R8R4      | DP32(8×4) → DP16(8×4) → DP8(8×4)                            |
|    6 | R8R8      | DP32(8×8) → DP16(8×8) → DP16(8×4) → DP8(8×4)                |
|    7 | R16R8     | DP16(16×8) → DP8(16×8) → DP8(16×4) → DP8(8×4)               |
|    8 | R16R16    | DP16(16×16) → DP8(16×16) → DP8(16×8) → DP8(16×4) → DP8(8×4) |
|    9 | R16R16    | DP8(16×16) → DP8(16×8) → DP8(16×4) → DP8(8×4)               |
|   10 | C8C8      | C-DP8 → DP16(8×8) → DP16(8×4) → DP8(8×4)                    |
|   11 | C8C8      | C-DP16 → DP32(8×8) → DP16(8×8) → DP16(8×4) → DP8(8×4)       |
|   12 | C16C16    | C-DP4 → DP8(16×16) → DP8(16×8) → DP8(16×4) → DP8(8×4)       |

*(Mode 4 — R16R16 4-parallel 1×4×1 — is unmappable on the 16-DP8 array: it needs 32 DP8 and,
being real with no re‖im pack, cannot reclaim the spare lanes. Excluded.)*

## How it maps to hardware

- The **chain length** sets which split each mode applies (index/length split, nibble split,
  byte split) → drives `sel_shift` and the per-DP8 `Weight` values.
- The **number of parallel results** sets the `pe_array` tap level read by `acc_array`
  (8→L0, 4→L1, 2→L2, 1→L3).
- See [`pe_array.md`](pe_array.md) (tree + shifts) and [`acc_array.md`](acc_array.md) (tap select)
  for the structures that realize these decompositions.
