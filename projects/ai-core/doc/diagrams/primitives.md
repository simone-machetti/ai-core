# primitives

Primitive-IP catalog for one PE — the **leaf building blocks at the diagram level**, each treated
as a black box. Their internals (Booth vs plain array, FA/HA composition, etc.) depend on
implementation choices not yet made and are intentionally out of scope here. Phase-A artifact.

> Naming follows the RTL convention used across the diagram docs — lowercase, `_i`/`_o`, `_n` = active-low.
> See [`pe_top.md`](pe_top.md) and the per-IP docs for where each primitive is instantiated.

**Every primitive is a general, parameterized module** — a single source reused across all its
instances (and across projects). The diagram labels (`8×4`, `4:2`, `<<8/0`, …) are just particular
parameterizations. "Configurable" is **compile-time (parameter)** unless it says runtime. Key
parameters are listed per primitive.

## Compute / arithmetic

| Primitive                              | Params                                    | Appears in               | Count       | Function                                                                                                                                                                                                                                          |
| -------------------------------------- | ----------------------------------------- | ------------------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **DP8** (`dp_8`)                       | — (fixed 8·8b×4b)                         | pe_array                 | 16          | Length-8 dot product `Σ aᵢ·bᵢ`; `booth_r4` + `cpr_w_n`; 17-bit carry-save output; per-operand runtime `is_signed_a_i`/`is_signed_b_i`. Fixed size, minimal widths.                                                                                |
| **Compressor** (`cpr_c_n` / `cpr_w_n`) | `IN_WIDTH`, `IN_SIZE`, `EXT`, `IS_SIGNED` | dp8, pe_array, acc_array | 16 + 15 + 8 | N:2 carry-save compressor, same interface, two builds: `cpr_c_n` serial cascade (min area, depth `IN_SIZE−2`), `cpr_w_n` Wallace tree (max throughput, ~log depth). 8:2 in DP, 4:2 tree, 3:2 lanes; compile-time `IS_SIGNED` for input extension. |
| **ADD** (`add_n`)                      | `WIDTH`                                   | acc_array                | 8           | Two-input adder, `WIDTH + 1` output (overflow-safe); runtime `is_signed_i`.                                                                                                                                                                       |

## Routing / glue

| Primitive               | Params                   | Appears in            | Count   | Function                                                                                                |
| ----------------------- | ------------------------ | --------------------- | ------- | ------------------------------------------------------------------------------------------------------- |
| **MUX (N→1)** (`mux_n`) | `WIDTH`, `SIZE`          | disp_array, acc_array | 16 + 16 | Operand block select (4→1); tap select (≤4→1) + accumulate select (2→1).                                |
| **Shifter** (`shift_n`) | `WIDTH`, `SIZE`, `SHIFT` | pe_array              | 14      | Conditional left-shift by `SHIFT` (width-growing) or pass-through; 1-bit `sel` + runtime `is_signed_i`. |
| **Gate-A** (`gate_a_n`) | `WIDTH`, `SIZE`          | acc_array             | 4       | Pass / zero (1-bit select); acc-lane carry enable / masking (`WIDTH = 1`).                              |
| **Gate-B** (`gate_b_n`) | `WIDTH`, `SIZE`          | disp_array            | 16      | Pass / zero / negate (2-bit select); operand-B masking (idle lanes) + sign negation (complex modes).    |

## State

| Primitive         | Params          | Appears in                      | Count     | Function                                                        |
| ----------------- | --------------- | ------------------------------- | --------- | --------------------------------------------------------------- |
| **REG** (`reg_n`) | `WIDTH`, `SIZE` | disp_array, pe_array, acc_array | 8 + 8 + 8 | Register bank (async `rst_ni`) — pipeline stages + accumulator. |

**8 primitives total.** Helpers also built: `ext_n` (`WIDTH`, `SIZE`, `EXT`; runtime `is_signed_i`),
the sign/zero extender reused inside the compressors / DP; and `fa` (1-bit full adder, reused from
ai-core-legacy) as the 3:2 cell inside the compressors; plus `booth_r4` + `booth_r4_cell` (radix-4
Booth, from ai-core-legacy, with per-operand runtime `is_signed_a_i`/`is_signed_b_i`) for the DP multiplier.

## Notes

- **Runtime vs parameter** — dimensions (widths, sizes, shift/ext amounts) are compile-time
  parameters; **signedness is a runtime input** (`is_signed_i`) on `shift_n`, `ext_n`, `add_n` (and
  per-operand on the DP) because it changes with the operating mode — e.g. the low word of a fused
  accumulator resolves unsigned while the high/standalone word resolves signed. The **compressors are
  the exception**: their signedness is a compile-time `IS_SIGNED` parameter, because a compressor's
  input signedness is fixed by where it sits in the datapath and never switches with the mode.
- **Compressor** — one `IN_SIZE`-parameterized IP for all arities (8:2, 4:2, 3:2), *not* a runtime
  mux: a node's arity is fixed by where it sits. Two interchangeable builds with the **same
  interface**: `cpr_c_n` (serial cascade, running pair seeded from the first two inputs, depth
  `IN_SIZE − 2`, minimal area) and `cpr_w_n` (Wallace tree, disjoint groups of three compressed in
  parallel per layer, ~`log₁.₅(IN_SIZE)` depth, max throughput). The CSA core (the `fa` rows) is
  signedness-agnostic, but both widen each input to `OUT_WIDTH`, so they take a compile-time
  `IS_SIGNED` parameter for that extension.
- **Gates** — `gate_b_n` (pass/zero/negate, 2-bit) handles operand B in `disp_array`: masking idle
  lanes (a lane is idled by zeroing its B, since `a·0 = 0`) and sign negation (complex modes 10–12).
  `gate_a_n` (pass/zero, 1-bit) is the acc-lane carry gate at `WIDTH = 1` in `acc_array`. `disp_array`
  needs no A gate. Their selects are the `ctr_*` / `prop_carry` signals in the diagrams.
- **DP8** (`dp_8`) is composite and **fixed to 8 lanes of int8·int4** (not parameterized — specialized
  for minimal width): 8 radix-4 Booth multipliers (`booth_r4`) → three per-weight Wallace compressions
  (`cpr_w_n`, 8:2, weights `2^0`/`2^2`/`2^4`) → sign-extend + weight-align the carry-save rows → final
  `cpr_w_n` (6:2) → 17-bit carry-save output. **Per-operand signedness** (`is_signed_a_i` /
  `is_signed_b_i`): each operand's high field is signed and low field unsigned, so all four sign combos
  occur; an unsigned `b` needs a **third** Booth partial product (weight `2^4`), `0` when `b` is signed.
  Fully carry-save (no resolve adders): each pair carries **one guard bit** to stay sign-consistent.
  The dot product spans 16 bits (`u×u` → `8·255·15 = 30600`, `u×s` → `−16320`); the final 6:2 takes no
  width growth (`EXT = 0`) and produces 18-bit rows (set by the weight-`2^4` aligned rows), of which the
  redundant top bit is dropped → a **17-bit** output (16-bit value + 1 guard, still sign-consistent).
- The **H/L split** in `disp_array` is bit-slicing / wiring, not a cell — so it is not a primitive.
- **Status** — all primitives built: `reg_n`, `mux_n`, `shift_n`, `add_n`, `ext_n`, `gate_a_n`,
  `gate_b_n`, `cpr_c_n`, `cpr_w_n`, `dp_8` (+ helpers `fa`, `booth_r4`, `booth_r4_cell`). Next: the
  sub-blocks (`disp_array`, `pe_array`, `acc_array`, `pe_ctrl`) and `pe_top`.
