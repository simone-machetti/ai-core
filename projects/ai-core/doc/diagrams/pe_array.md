# pe_array

Design doc and companion for [`pe_array.excalidraw`](pe_array.excalidraw). The 16-DP8 carry-save reduction tree.

> Figure labels are uppercase; this doc uses the RTL convention — lowercase, `_i`/`_o`, `_n` = active-low.

## Purpose

Instantiate the 16 `dp_8` cores and reduce their carry-save outputs through a 4-level tree with programmable per-level shifts, exposing a carry-save tap at every level so a mode reads its results at the depth matching its output count (8 results → L0, 4 → L1, 2 → L2, 1 → L3). Fixed to the PE; the DP8s live here and get their per-lane signedness from `pe_ctrl`.

## Interface

| Signal              | Dir | Width   | Description                                                     |
| ------------------- | --- | ------- | -------------------------------------------------------------- |
| `clk_i`             | in  | 1       | Clock.                                                         |
| `rst_ni`            | in  | 1       | Async active-low reset.                                        |
| `a_dp8_i[0:15]`     | in  | 64 each | A operand per DP8 (8 × int8), from `disp_array`.               |
| `b_dp8_i[0:15]`     | in  | 32 each | B operand per DP8 (8 × int4), from `disp_array`.               |
| `is_signed_a_i[0:15]`| in | 1 each  | Per-DP8 multiplicand signedness, from `pe_ctrl`.               |
| `is_signed_b_i[0:15]`| in | 1 each  | Per-DP8 multiplier signedness, from `pe_ctrl`.                 |
| `sel_shift_i[2:0]`  | in  | 1 each  | Per-level shift enable: `[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`. |
| `l0_sum_o[0:7]` / `l0_carry_o[0:7]`   | out | 17 each | L0 taps (carry-save). |
| `l1_sum_o[0:3]` / `l1_carry_o[0:3]`   | out | 29 each | L1 taps.              |
| `l2_sum_o[0:1]` / `l2_carry_o[0:1]`   | out | 37 each | L2 taps.              |
| `l3_sum_o` / `l3_carry_o`             | out | 39      | L3 tap.               |

Taps are carry-save (`sum + carry`); wide taps get split into 20-bit H/L halves by `acc_array` (done there, not here). All operands and taps are signed, so the tree compressors, shifters, and extenders run signed (`IS_SIGNED = 1'b1`, compile-time).

## Internal structure

16 DP8 → 8× CPR 4:2 (L0, registered) → 4× (L1) → 2× (L2) → 1× (L3). Per CPR node: a `shift_n` on the higher-weight operand (conditional `<<s`, or sign-extend when unshifted) and an `ext_n` on the other operand to align it to the same width — **both signed** (`IS_SIGNED(1'b1)`; the tree carries signed carry-save values throughout). Counts: 16 `dp_8`, 15 `cpr_w_n` 4:2 (8+4+2+1), 14 `shift_n` (8 `<<8` at L0, 4 `<<4` at L1, 2 `<<8` at L2), 15 `ext_n` (one per CPR), 8 `reg_n` (L0 only). `sel_shift` is one enable per level, shared by every node at that level.

**Crossover at L0 (mind this — connections cross the `disp_array` 2×DP8 pairs).** The L0 CPRs combine DP8s two apart, so a node mixes DP8s from two different `disp_array` pairs: `l0[2g] = dp8[4g] + dp8[4g+2]`, `l0[2g+1] = dp8[4g+1] + dp8[4g+3]`:

| L0 node | DP8s combined | | L0 node | DP8s combined |
| ------- | ------------- |-| ------- | ------------- |
| `l0[0]` | dp8 0 + dp8 2 | | `l0[4]` | dp8 8 + dp8 10 |
| `l0[1]` | dp8 1 + dp8 3 | | `l0[5]` | dp8 9 + dp8 11 |
| `l0[2]` | dp8 4 + dp8 6 | | `l0[6]` | dp8 12 + dp8 14 |
| `l0[3]` | dp8 5 + dp8 7 | | `l0[7]` | dp8 13 + dp8 15 |

L1/L2/L3 combine straight-binary adjacent nodes: `l1[j] = l0[2j] + l0[2j+1]`, `l2[k] = l1[2k] + l1[2k+1]`, `l3 = l2[0] + l2[1]`.

## Bit widths

Value bits (magnitude + sign) needed at each level a mode passes through (**bold** = the tap that mode reads):

| Mode | Prec    | Tap | L0 | L1 | L2 | L3 |
| ---- | ------- | --- | -- | -- | -- | -- |
| 1    | R8R4    | L0  | **16** | –  | –  | –  |
| 2    | R8R8    | L1  | 17 | **21** | –  | –  |
| 3    | R16R8   | L1  | 24 | **28** | –  | –  |
| 5    | R8R4    | L2  | 16 | 17 | **18** | –  |
| 6    | R8R8    | L3  | 17 | 21 | 22 | **23** |
| 7    | R16R8   | L2  | 24 | 28 | **29** | –  |
| 8    | R16R16  | L3  | 24 | 28 | 36 | **37** |
| 9    | R16R16  | L2  | 24 | 28 | **36** | –  |
| 10   | C8C8    | L2  | 17 | 22 | **23** | –  |
| 11   | C8C8    | L3  | 17 | 22 | 23 | **24** |
| 12   | C16C16  | L3  | 24 | 29 | 37 | **38** |
| **worst** | |  | **24** | **29** | **37** | **38** |

`L0 = 24` in the R16 rows is the internal `<<8` intermediate, not a tap. Each DP8 output is 16-bit value / 17-bit carry-save; the growth is the shift plus the summed terms.

**Datapath width** = value + 1 guard bit, built as `17 (DP8) + shift + EXT` per level, where `shift = [8, 4, 8, 0]` (the shifters) and the compressor `EXT = [0, 1, 0, 1]`:

| Level | IN_WIDTH (= prev + shift) | `EXT` | node width (OUT) |
| ----- | ------------------------- | ----- | ---------------- |
| DP8   | —                         | —     | 17               |
| L0    | 17 + **8** = 25           | **+0**| **25**           |
| L1    | 25 + **4** = 29           | **+1**| **30**           |
| L2    | 30 + **8** = 38           | **+0**| **38**           |
| L3    | 38 + **0** = 38           | **+1**| **39**           |

- **`EXT = 0` at L0 / L2** — the level *has* a shift, so `IN_WIDTH = prev + shift` already gives the shifted operand room; the value + 1 guard just fits (e.g. L0: value 24 + guard = 25 = IN_WIDTH). No extra bit. (Same as `dp_8`'s final CPR with `EXT = 0`.)
- **`EXT = 1` at L1 / L3** — driven by the complex modes (C16C16), where `Re = ac − bd` sums two products and needs one more bit than the real path.

**Node vs tap.** The `node` width above is the CPR output that feeds the *next* level — sized for the worst intermediate across **all** modes. The **tap** to the acc is narrower: it only has to hold the modes that *read* that level, so it is `(reading-mode value) + 1 guard` (a non-reading mode's tap is a don't-care). Each tap is the low slice of its node:

| Level | node | tap    | tap = reading-mode value + guard |
| ----- | ---- | ------ | -------------------------------- |
| L0    | 25   | **17** | mode 1: 16 + 1                   |
| L1    | 30   | **29** | mode 3: 28 + 1                   |
| L2    | 38   | **37** | mode 9: 36 + 1                   |
| L3    | 39   | **39** | mode 12: 38 + 1                  |

The L0 register stays **25-bit** (the R16 modes' `<<8` intermediate must feed L1 at full precision); only its **low 17 bits** leave as the tap. The acc sign-extends each tap into its 20-/40-bit lane.

## Tap selection

| Result nodes | Tap  | Real modes | Complex modes                                  |
| ------------ | ---- | ---------- | ---------------------------------------------- |
| 8            | `l0` | 1          | —                                              |
| 4            | `l1` | 2, 3       | 10 (2× `[Re,Im]` at `l1[0..3]`)                |
| 2            | `l2` | 5, 7, 9    | 11, 12 (`Re` at `l2[0]`, `Im` at `l2[1]`)      |
| 1            | `l3` | 6, 8       | —                                              |

A complex output occupies **two adjacent nodes** (Re then Im), so it reads one level *shallower* than a real result of the same count: mode 10 (2 complex results) at `l1`, modes 11/12 (1 complex result) at `l2`. Reading them at `l2`/`l3` would give `Re+Im` summed, not the separate parts.

The shift enables follow the operand split: `sel_shift[0] = 1` iff A is 16-bit, `[1] = 1` iff B ≥ 8-bit, `[2] = 1` iff B is 16-bit (validated against every mode's max weight in `modes.xlsx`).

## Notes

- `is_signed_a`/`is_signed_b` are per-DP8 controls from `pe_ctrl` — the 16 DP8s are instantiated here.
- `REG` at L0 only; L1–L3 combinational (one pipeline stage inside `pe_array`).
- Wire the L0 crossover as tabulated above (crossed, not adjacent) — this is the cross-boundary connection between `disp_array` pairs.
