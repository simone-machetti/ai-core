# Accumulator Array (Square)

`acc_array_sqr` — the final stage of the **square** PE. Same eight-lane / lane-pair-fusion shape as [acc_array](./acc_array.md), but it resolves the square reconstruction `out = ½(PE − α − β + C)` as a pure carry-save **add** — no subtractor, no carry-in injection — then applies the exact `÷2`. It consumes three tap sets in parallel ([pe_array_sqr](./pe_array_sqr.md), [pe_array_alpha_sqr](./pe_array_alpha_sqr.md), [pe_array_beta_sqr](./pe_array_beta_sqr.md)) plus the per-mode constant from [const_sqr](./const_sqr.md).

## Purpose

The α/β generators already emit **`−α`/`−β`** (one's-complemented taps) and `const_sqr` folds every `+1`/`+2` deferral into one constant `C`, so the resolve is a plain add of eight rows: `PE(sum,carry) + (−α)(sum,carry) + (−β)(sum,carry) + C + acc`. There is no subtractor and no carry-in. Per lane:

- **Tap mux** ([mux_n](./mux_n.md), `sel_out_i`) selects the read level for each of the three operands → **6 rows** (a sum/carry pair each), windowed to 20-bit exactly as `acc_array` does (sign-extend the tap to 40-bit; even lane = high half `[39:20]`, odd = low `[19:0]`; L0 single-lane).
- **Acc mux** ([mux_n](./mux_n.md), `sel_acc_i`) picks the external seed `acc_i` or the register feedback; its output is then **left-shifted `<<1`** so the accumulated term enters at 2×. For a fused pair the low lane's shifted-out MSB fills the high lane's LSB, gated by `fused` through a [gate_n](./gate_n.md) (`WIDTH=1`) so single-lane L0 outputs get `0`. This lets `acc_i`/`pe_out` stay in native units while the register holds the **true** value.
- **Const mux** ([mux_n](./mux_n.md), `SIZE=4`, `sel_const_i`) selects the per-mode `C` from `const_sqr`: `CH`/`CL` (`c_o` hi/lo) on the Im/real outputs, `RH`/`RL` (`c_neg` hi/lo) on the HW-negated Re outputs, with **`RH = sign(RL)`** (the Re constant fits the low 20; its high half is the sign-extension). Its four inputs are the four `sel_const_i` patterns (see below); the even/odd and Re-lane picks fold to constants at elaboration.
- **CPR 8:2** ([cpr_w_n](./cpr_w_n.md), `EXT=3`) folds the 8 rows `{6 taps, C, 2·acc}` to two; **`add_n`** ([add_n](./add_n.md)) resolves them plus the inter-lane carry into the 20-bit window (`= 2·R_new`).
- **`÷2`**: an arithmetic `>>1` between `add_n` and the register, with an **`H→L` cross-lane bit** (the high lane's shifted-out LSB fills the low lane's MSB on fused outputs). The register ([reg_n](./reg_n.md)) holds the true result `R_new = ½·tap + acc` — no decay, no 2× register.
- **Inter-lane carry** ([gate_n](./gate_n.md), `prop_carry_i`) chains `L(odd) → H(even).cin` (3 bits here — 8 rows overflow bit 19 by up to 3); the `<<1`'s low-lane overflow rides this same chain.

Pipeline depth is identical to `acc_array` — one register stage; the PE/α/β arrays that feed it run in parallel.

## `sel_const_i` patterns

`RH = sign(RL)` and `c_neg` reaches the Re output only on the **HW-negated** complex modes:

| `sel_const_i` | modes                    | const per lane                                                   |
| ------------- | ------------------------ | ---------------------------------------------------------------- |
| `0`           | 1                        | all lanes `CL` (single-lane L0 outputs)                          |
| `1`           | 2/3/5/6/7/8/9 **and 12** | even `CH`, odd `CL` — `c_o` on every half                        |
| `2`           | 10                       | Re pairs (0,1)(4,5) → `RH`/`RL`; Im pairs (2,3)(6,7) → `CH`/`CL` |
| `3`           | 11                       | Re pair (2,3) → `RH`/`RL`; Im pair (6,7) → `CH`/`CL`             |

Mode 12 (C16×C16) is **software pre-negated** — it has no `comp_n`, so the `im·im` centering does not cancel in `Re`; its Re output takes `c_o` like the Im half, hence pattern `1` (not a `c_neg` pattern). See [const_sqr](./const_sqr.md).

## Parameters

None — fixed to the PE configuration; the key `localparam`s:

| Localparam               | Value             | Meaning                                          |
| ------------------------ | ----------------- | ------------------------------------------------ |
| `NUM_LANE`               | 8                 | Accumulation lanes (one per output).             |
| `PE_WIDTH`               | 20                | Per-lane / `pe_out` width (true result).         |
| `FUSE`                   | 40                | Sign-extended tap width used for windowing.      |
| `NUM_OP`                 | 3                 | Tap operands folded per lane: PE, `−α`, `−β`.    |
| `EXT` / `CARRY`          | 3 / 3             | CPR 8:2 guard bits / inter-lane carry (8 rows).  |
| `L0_TAP`…`L3_TAP`        | 19 / 30 / 38 / 39 | Square `pe_array` tap widths (carry-save pairs). |
| `C_WIDTH` / `CNEG_WIDTH` | 32 / 8            | `const_sqr` `c_o` / `c_neg_o` widths.            |
| `SEL_WIDTH`              | 2                 | Tap-level and const-pattern select.              |

## Interface

| Signal                             | Dir | Width   | Description                                                             |
| ---------------------------------- | --- | ------- | ----------------------------------------------------------------------- |
| `clk_i` / `rst_ni`                 | in  | 1       | Clock / async active-low reset.                                         |
| `pe_l0_sum_i`/`pe_l0_carry_i[0:7]` | in  | 19 each | PE L0 tap pairs (L1/L2/L3: 30/38/39, `[0:3]`/`[0:1]`/scalar).           |
| `a_l0_sum_i` … `a_l3_carry_i`      | in  | 19…39   | `−α` tap pairs (same shape as PE), from `pe_array_alpha_sqr`.           |
| `b_l0_sum_i` … `b_l3_carry_i`      | in  | 19…39   | `−β` tap pairs (same shape as PE), from `pe_array_beta_sqr`.            |
| `c_i`                              | in  | 32      | Positive constant (`C_real+4`), from `const_sqr`'s `c_o`.               |
| `c_neg_i`                          | in  | 8       | Signed Re constant (`4−2N`), from `const_sqr`'s `c_neg_o`.              |
| `acc_i[0:7]`                       | in  | 20 each | External seed, **native units** (the `<<1` doubles it inside).          |
| `sel_out_i`                        | in  | 2       | Tap-level select (shared): which tree level all lanes read.             |
| `sel_acc_i`                        | in  | 1       | Acc mux (shared): `0` = `acc_i`, `1` = register feedback.               |
| `sel_const_i`                      | in  | 2       | Const-mux pattern (shared) — see table above.                           |
| `prop_carry_i`                     | in  | 1       | Inter-lane carry-chain enable (shared): lane fusion.                    |
| `pe_out_o[0:7]`                    | out | 20 each | Per-lane true results; a fused result is `{pe_out[even], pe_out[odd]}`. |

## Instantiation

```systemverilog
acc_array_sqr acc_array_sqr_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .pe_l0_sum_i(pe_l0_sum), .pe_l0_carry_i(pe_l0_carry), /* … pe l1/l2/l3 … */
    .a_l0_sum_i(a_l0_sum),   .a_l0_carry_i(a_l0_carry),   /* … a  l1/l2/l3 … */
    .b_l0_sum_i(b_l0_sum),   .b_l0_carry_i(b_l0_carry),   /* … b  l1/l2/l3 … */
    .c_i(c_o), .c_neg_i(c_neg_o),
    .acc_i(acc_word),
    .sel_out_i(sel_out), .sel_acc_i(sel_acc),
    .sel_const_i(sel_const), .prop_carry_i(prop_carry),
    .pe_out_o(pe_out)
);
```

## Verification

[tb_acc_array_sqr](../testbenches/tb_acc_array_sqr.md) wires the whole square path — dispatchers → `pe_array_sqr` ∥ `pe_array_alpha_sqr` ∥ `pe_array_beta_sqr` → `const_sqr` → `acc_array_sqr` — and checks `pe_out` as a plain matrix multiply, reusing the baseline `tb_acc_array` golden verbatim (the square path is bit-exact to the multiply path). All 11 modes × 2000 corner-biased vectors, single-shot and accumulation, 0 mismatches, `-Wall` clean.

Source: [acc_array_sqr.sv](../../rtl/acc_array_sqr.sv)
