# top_8x8_bas

Companion description for [`top_8x8_bas.excalidraw`](./top_8x8_bas.excalidraw). Chip-level PE array.

> **Out of current prototype scope** — this effort stops at [`top_pe_bas`](./top_pe_bas.excalidraw). Documented here
> for completeness so the top-level intent is on record.

## Purpose

The full AI-Core: an **8×8 grid of 64 Processing Elements**, each PE = one [`top_pe_bas`](./top_pe_bas.excalidraw)
(128 8b×4b MACs). The figure shows the 64-cell grid, each cell labelled `PE (128 MAC)` — i.e. the
chip is the reconfigurable PE replicated as a matrix engine.

## Interface

Not yet drawn — the figure shows only the PE tiling, no I/O wiring. To be defined when/if the
chip level is taken on. Expected shape (placeholder, **TBD**):

| Group             | Direction | Notes                                                        |
| ----------------- | --------- | ------------------------------------------------------------ |
| Operand feed      | in        | How A/B stream/broadcast into the 8 rows / 8 columns of PEs. |
| Mode/control      | in        | Per-PE vs broadcast `mode_i` and control.                    |
| Result collection | out       | How the 64 PEs' `pe_out_o` are gathered/reduced.             |
| `clk_i`, `rst_ni` | in        | Clock / reset distribution.                                  |

## High-level behavior

Each cell runs the same reconfigurable PE; the matrix arrangement performs a tiled MatMul, with
dataflow (systolic vs broadcast, stationary operand, accumulation across tiles) **to be decided**
at the chip stage. No per-PE behavior beyond [`top_pe_bas`](./top_pe_bas.excalidraw) is implied by this figure.

## Open items

- Entire chip-level interface and dataflow — deferred.
- Whether each PE has independent `mode_i` or a shared one.
- Inter-PE operand reuse / result reduction network.
