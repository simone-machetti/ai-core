# pe_array

Design doc and companion for [`pe_array.excalidraw`](pe_array.excalidraw). The 16-DP8 carry-save reduction tree.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

## Purpose

Instantiate the 16 `dp_8` cores and reduce their carry-save outputs through a 4-level tree with programmable per-level shifts, exposing a carry-save tap at every level so a mode reads its results at the depth matching its output count (8 results → L0, 4 → L1, 2 → L2, 1 → L3). Fixed to the PE; the DP8s live here and get their per-lane signedness from `pe_ctrl`.

## Interface

| Signal                              | Dir | Width   | Description                                                             |
| ----------------------------------- | --- | ------- | ----------------------------------------------------------------------- |
| `clk_i`                             | in  | 1       | Clock.                                                                  |
| `rst_ni`                            | in  | 1       | Async active-low reset.                                                 |
| `a_dp8_i[0:15]`                     | in  | 64 each | A operand per DP8 (8 × int8), from `disp_array`.                        |
| `b_dp8_i[0:15]`                     | in  | 32 each | B operand per DP8 (8 × int4), from `disp_array`.                        |
| `is_signed_a_i[0:15]`               | in  | 1 each  | Per-DP8 multiplicand signedness, from `pe_ctrl`.                        |
| `is_signed_b_i[0:15]`               | in  | 1 each  | Per-DP8 multiplier signedness, from `pe_ctrl`.                          |
| `sel_shift_i[2:0]`                  | in  | 1 each  | Per-level shift enable: `[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`. |
| `l0_sum_o[0:7]` / `l0_carry_o[0:7]` | out | 18 each | L0 taps (carry-save).                                                   |
| `l1_sum_o[0:3]` / `l1_carry_o[0:3]` | out | 29 each | L1 taps.                                                                |
| `l2_sum_o[0:1]` / `l2_carry_o[0:1]` | out | 37 each | L2 taps.                                                                |
| `l3_sum_o` / `l3_carry_o`           | out | 38      | L3 tap.                                                                 |

Taps are carry-save (`sum + carry`); wide taps get split into 20-bit H/L halves by `acc_array` (done there, not here). All operands and taps are signed, so the tree compressors, shifters, and extenders run signed (`IS_SIGNED = 1'b1`, compile-time).

## Internal structure

16 DP8 → 8× CPR 4:2 (L0, registered) → 4× (L1) → 2× (L2) → 1× (L3). Per CPR node: a `shift_n` on the higher-weight operand (conditional `<<s`, or sign-extend when unshifted) and an `ext_n` on the other operand to align it to the same width — **both signed** (`IS_SIGNED(1'b1)`; the tree carries signed carry-save values throughout). Counts: 16 `dp_8`, 15 `cpr_w_n` 4:2 (8+4+2+1), 14 `shift_n` (8 `<<8` at L0, 4 `<<4` at L1, 2 `<<8` at L2), 14 `ext_n` (one per shifting node, L0–L2; L3 takes its two L2 operands at equal weight, no shift/ext), 2 `reg_n` banks (L0 `sum` + `carry`, 8-wide each). `sel_shift` is one enable per level, shared by every node at that level.

**Crossover at L0 (mind this — connections cross the `disp_array` 2×DP8 pairs).** The L0 CPRs combine DP8s two apart, so a node mixes DP8s from two different `disp_array` pairs: `l0[2g] = dp8[4g] + dp8[4g+2]`, `l0[2g+1] = dp8[4g+1] + dp8[4g+3]`:

| L0 node | DP8s combined |     | L0 node | DP8s combined   |
| ------- | ------------- | --- | ------- | --------------- |
| `l0[0]` | dp8 0 + dp8 2 |     | `l0[4]` | dp8 8 + dp8 10  |
| `l0[1]` | dp8 1 + dp8 3 |     | `l0[5]` | dp8 9 + dp8 11  |
| `l0[2]` | dp8 4 + dp8 6 |     | `l0[6]` | dp8 12 + dp8 14 |
| `l0[3]` | dp8 5 + dp8 7 |     | `l0[7]` | dp8 13 + dp8 15 |

L1/L2/L3 combine straight-binary adjacent nodes: `l1[j] = l0[2j] + l0[2j+1]`, `l2[k] = l1[2k] + l1[2k+1]`, `l3 = l2[0] + l2[1]`.

## Bit widths

Value bits (magnitude + sign) at each level a mode passes through — **pure value, no guard bit** (**bold** = the tap that mode reads, `–` = never reached). The tap value is the closed form `Pa + Pb + log₂K` (real), `+ 1` for complex (the `Im = ad + bc` term hits an exact power of two); intermediate levels are the worst-case magnitude the arithmetic reaches there.

The R16R16 modes (8, 9, 12) share their L0/L1 values (`23 / 27`) with the R16R8 modes (3, 7): B's high byte enters only at **L2** (`sel_shift[2] = <<8`), so through L0 and L1 an R16R16 datapath is byte-for-byte identical to R16R8. B's second byte adds its `<<8` weight at L2 (`27 → 35`), and L3 combines the two L2 nodes (`35 → 36`).

| Mode | Prec   | Tap | L0     | L1     | L2     | L3     |
| ---- | ------ | --- | ------ | ------ | ------ | ------ |
| 1    | R8R4   | L0  | **16** | –      | –      | –      |
| 2    | R8R8   | L1  | 16     | **20** | –      | –      |
| 3    | R16R8  | L1  | 23     | **27** | –      | –      |
| 5    | R8R4   | L2  | 16     | 16     | **17** | –      |
| 6    | R8R8   | L3  | 16     | 20     | 21     | **21** |
| 7    | R16R8  | L2  | 23     | 27     | **28** | –      |
| 8    | R16R16 | L3  | 23     | 27     | 35     | **36** |
| 9    | R16R16 | L2  | 23     | 27     | **35** | –      |
| 10   | C8C8   | L1  | 16     | **20** | –      | –      |
| 11   | C8C8   | L2  | 16     | 20     | **21** | –      |
| 12   | C16C16 | L2  | 23     | 27     | **35** | –      |

**Worst case per level.** Left: the worst over **every** mode that reaches the level — sizes the **node** that feeds the next level. Right: the worst over only the modes that **exit** (read their tap) at the level — sizes the exported **tap**.

| Level | Worst — all modes through | Worst — modes exiting here |
| ----- | ------------------------- | -------------------------- |
| L0    | 23 (modes 3, 7, 8, 9, 12) | 16 (mode 1)                |
| L1    | 27 (modes 3, 7, 8, 9, 12) | 27 (mode 3)                |
| L2    | 35 (modes 8, 9, 12)       | 35 (modes 9, 12)           |
| L3    | 36 (mode 8)               | 36 (mode 8)                |

These are pure values; the RTL carries carry-save guard bits on top. The DP8 delivers its result as a **20-bit** sign-consistent carry-save pair — 16-bit value plus 4 guard bits (a redundant carry-save pair needs headroom beyond the resolved value or its top carry is lost, see [`dp_8`](../../rtl/dp_8.sv)). Those 4 guard bits are enough headroom for the whole tree, so every compressor runs `EXT = 0` and each node is just `20 (DP8) + shift` with `shift = [8,4,8,0]`, giving **28 / 32 / 40 / 40**.

Each tap is the output of a 4:2 compressor, so its minimum sign-consistent width is `worst-exit value + 2` (the two compressor guard bits): **18 / 29 / 37 / 38** for L0..L3 (`16+2`, `27+2`, `35+2`, `36+2`). The L0 register keeps the full 28-bit node (the R16 `<<8` intermediate must feed L1 un-truncated); only the low 18 bits leave as the L0 tap. Verified sign-consistent across all 11 modes under corner-biased operands (most-negative / max-positive lanes) — the regime that first exposed the DP8 guard-bit loss.

## Tap selection

| Result nodes | Tap  | Real modes | Complex modes                             |
| ------------ | ---- | ---------- | ----------------------------------------- |
| 8            | `l0` | 1          | —                                         |
| 4            | `l1` | 2, 3       | 10 (2× `[Re,Im]` at `l1[0..3]`)           |
| 2            | `l2` | 5, 7, 9    | 11, 12 (`Re` at `l2[0]`, `Im` at `l2[1]`) |
| 1            | `l3` | 6, 8       | —                                         |

A complex output occupies **two adjacent nodes** (Re then Im), so it reads one level *shallower* than a real result of the same count: mode 10 (2 complex results) at `l1`, modes 11/12 (1 complex result) at `l2`. Reading them at `l2`/`l3` would give `Re+Im` summed, not the separate parts.

The shift enables follow the operand split: `sel_shift[0] = 1` iff A is 16-bit, `[1] = 1` iff B ≥ 8-bit, `[2] = 1` iff B is 16-bit (validated against every mode's max weight in `modes.xlsx`).

## Notes

- `is_signed_a`/`is_signed_b` are per-DP8 controls from `pe_ctrl` — the 16 DP8s are instantiated here.
- `REG` at L0 only; L1–L3 combinational (one pipeline stage inside `pe_array`).
- Wire the L0 crossover as tabulated above (crossed, not adjacent) — this is the cross-boundary connection between `disp_array` pairs.
