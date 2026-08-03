# Accumulator Array (BFP)

`acc_array_bfp` — the BFP variant of [acc_array](./acc_array.md). Same eight-lane / lane-pair-fusion shape (window the tap, tap-level MUX, accumulate MUX, CPR 3:2, [add_n](./add_n.md), L→H carry chain, output register), plus one [align_cell_bfp](./align_cell_bfp.md) per lane between the accumulate MUX and the CPR, and an exponent sideband that tracks a **running accumulator scale**. With all exponents equal every aligner is bit-transparent, so the BFP path is bit-identical to the plain-integer [acc_array](./acc_array.md).

## Purpose

The accumulator is where the tap a mode reads meets the running or external accumulator, and in BFP those two can sit at different scales. So each lane inserts an aligner before the fold: it brings the accumulator row and the tap `(sum, carry)` pair to their common scale `max(acc_exp, tap_exp)`, the smaller-exponent side arithmetic-right-shifted (truncating), then the CPR 3:2 compresses the three aligned rows exactly as in the baseline. Node and guard widths are unchanged — an aligned addend is a right-shifted (smaller) version of its integer worst case — so the mantissa datapath is [acc_array](./acc_array.md) verbatim; this page covers the exponent path and the aligner wiring.

- **Two exponent MUXes mirror the two data MUXes.** A per-lane OUT MUX EXP ([mux_n](./mux_n.md), `sel_out_i`) picks the tap scale from the [pe_array_bfp](./pe_array_bfp.md) tap exponents, following the same window map as the data (`L0→[g]`, `L1→[g/2]`, `L2→[0/1]` on lanes 2,3,6,7, `L3` on lanes 6,7; idle levels tied to the minimum scale `0`). A per-lane ACC MUX EXP ([mux_n](./mux_n.md), `sel_acc_i`) picks the seed scale `acc_exp_i` or the lane's own registered scale, matching the mantissa accumulate MUX.
- **A running scale register.** The aligner emits `max(acc_exp, tap_exp)`; an exponent register per lane (loaded every cycle, reset to the minimum scale `0`) holds it as the running accumulator scale and drives `pe_exp_o`. The seed and the feedback share **one format** — a 20-bit mantissa (40-bit split H/L over a fused pair) plus a 7-bit product-domain scale — so the two accumulate MUXes just select between same-shape operands; the datapath carries no bias constant.
- **Lane fusion is a second crossing bus.** Fused pairs run an **H→L fill chain** through the two aligners, opposite in direction to the existing L→H adder-carry chain — see [Lane fusion](#lane-fusion-the-hl-fill-chain).

Pipeline depth is identical to `acc_array` — one register stage.

## Parameters

None — fixed to the PE configuration; the key `localparam`s (identical to [acc_array](./acc_array.md) plus the exponent path):

| Localparam            | Value             | Meaning                                                                    |
| --------------------- | ----------------- | -------------------------------------------------------------------------- |
| `NUM_LANE`            | 8                 | Accumulation lanes (one per output).                                       |
| `PE_WIDTH`            | 20                | Per-lane / `pe_out` width.                                                 |
| `FUSE`                | 40                | Sign-extended tap width used for windowing.                                |
| `CPR_WIDTH`           | 22                | CPR 3:2 / `add_n` width (`PE_WIDTH + 2`).                                  |
| `CARRY`               | 2                 | Inter-lane (L→H) carry width — three 20-bit rows.                          |
| `L0_WIDTH`…`L3_WIDTH` | 18 / 29 / 37 / 38 | `pe_array_bfp` tap widths (carry-save pairs).                              |
| `SEL_WIDTH`           | 2                 | Tap-level select.                                                          |
| `EXP_WIDTH`           | 7                 | **NEW** — product-domain scale width (`e_A + e_B`).                        |
| `ROWS`                | 3                 | **NEW** — rows the aligner spans (1 acc + 2 tap) and the fill-chain width. |

## Interface

| Signal                       | Dir | Width   | Description                                                        |
| ---------------------------- | --- | ------- | ------------------------------------------------------------------ |
| `clk_i` / `rst_ni`           | in  | 1       | Clock / asynchronous active-low reset.                             |
| `l0_sum_i`/`l0_carry_i[0:7]` | in  | 18 each | L0 tap pairs, from `pe_array_bfp` (L1/L2/L3: 29/37/38).            |
| `l1_sum_i` … `l3_carry_i`    | in  | 29…38   | L1/L2/L3 tap pairs (`[0:3]`/`[0:1]`/scalar).                       |
| `l0_exp_i[0:7]`              | in  | 7 each  | **NEW** — L0 tap scales (L1/L2/L3: `[0:3]`/`[0:1]`/scalar).        |
| `l1_exp_i` … `l3_exp_i`      | in  | 7 each  | **NEW** — L1/L2/L3 tap scales, from `pe_array_bfp`.                |
| `acc_i[0:7]`                 | in  | 20 each | External accumulator word, one per lane.                           |
| `acc_exp_i[0:7]`             | in  | 7 each  | **NEW** — external seed scale (product-domain), one per lane.      |
| `sel_out_i`                  | in  | 2       | Tap-level select (shared): which tree level all lanes read.        |
| `sel_acc_i`                  | in  | 1       | Accumulate MUX (shared): `0` = `acc_i`, `1` = register feedback.   |
| `prop_carry_i`               | in  | 1       | Inter-lane carry-chain / fusion enable (shared): lane fusion.      |
| `pe_out_o[0:7]`              | out | 20 each | Per-lane results; a fused result is `{pe_out[even], pe_out[odd]}`. |
| `pe_exp_o[0:7]`              | out | 7 each  | **NEW** — per-lane running accumulator scale.                      |

## Instantiation

```systemverilog
acc_array_bfp acc_array_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .l0_sum_i(l0_sum), .l0_carry_i(l0_carry), /* … l1/l2/l3 … */
    .l0_exp_i(l0_exp), .l1_exp_i(l1_exp), .l2_exp_i(l2_exp), .l3_exp_i(l3_exp),
    .acc_i(acc_word), .acc_exp_i(acc_exp_word),
    .sel_out_i(sel_out), .sel_acc_i(sel_acc), .prop_carry_i(prop_carry),
    .pe_out_o(pe_out), .pe_exp_o(pe_exp)
);
```

## Internal logic

Everything is one per-lane generate loop, as in [acc_array](./acc_array.md): the tap windowing, the tap-level MUX, the accumulate MUX, the CPR 3:2, the `add_n` resolve, the L→H carry chain and the output register are unchanged. The BFP additions are the exponent MUXes, the aligner, and the exponent register.

### The two exponent MUXes

Each lane packs its per-level tap scales into `w_exp[g]` — following the same window map as the data (`L0→[g]`, `L1→[g/2]`, `L2→[N2]` on lanes 2,3,6,7, `L3` on lanes 6,7; missing levels tied to `'0`) — and selects the tap scale with the shared `sel_out_i`, exactly alongside the data tap MUX:

```systemverilog
mux_n #(.WIDTH(EXP_WIDTH), .SIZE(NUM_LVL)) tap_mux_exp_i (
    .in_i(w_exp[g]), .sel_i(sel_out_i), .out_o(tap_exp)
);
```

A second `mux_n` picks the accumulator scale — the external seed `acc_exp_i[g]` or the lane's registered scale — under the shared `sel_acc_i`, mirroring the data accumulate MUX:

```systemverilog
assign accmux_exp_in[0] = acc_exp_i[g];
assign accmux_exp_in[1] = reg_exp_q[g];
mux_n #(.WIDTH(EXP_WIDTH), .SIZE(2)) acc_mux_exp_i (
    .in_i(accmux_exp_in), .sel_i(sel_acc_i), .out_o(acc_exp_sel)
);
```

### The per-lane aligner

The aligner takes the selected accumulator row (`SIZE_0 = 1`) at `acc_exp_sel` and the tap `(sum, carry)` pair (`SIZE_1 = 2`) at `tap_exp`, brings all three rows to `max` (smaller side arithmetic-right-shifted, truncating), and emits that `max` as `align_exp`. Its three outputs feed the CPR 3:2 in place of the raw rows:

```systemverilog
align_cell_bfp #(
    .WIDTH(PE_WIDTH), .SIZE_0(1), .SIZE_1(2), .EXP_WIDTH(EXP_WIDTH), .IS_SIGNED(1'b1)
) align_cell_bfp_i (
    .in_0_i(acc_row),  .exp_0_i(acc_exp_sel),
    .in_1_i(tap_pair), .exp_1_i(tap_exp),
    .chain_en_i(chain_en), .chain_0_i(chain_acc_i), .chain_1_i(chain_tap_i),
    .chain_0_o(chain_acc_o), .chain_1_o(chain_tap_o),
    .out_o(align_out), .exp_o(align_exp)
);
```

### Lane fusion (the H→L fill chain)

Fused pairs (`(0,1)(2,3)(4,5)(6,7)`, even = H / odd = L) form one distributed 40-bit three-row shifter. The **even (H)** lane runs standalone (`chain_en = 0`, chain inputs zero) but exports its three shifted-out fill rows — acc, tap sum, tap carry — on `chain_row[g]`. The **odd (L)** lane takes its fill from that chain instead of sign replication, gated by `prop_carry` through a single [gate_n](./gate_n.md) so an unfused (single-lane) alignment falls back to independent sign-fill:

```systemverilog
gate_n #(.WIDTH(PE_WIDTH), .SIZE(ROWS)) gate_n_align_i (
    .in_i(chain_row[g-1]), .sel_i(~prop_carry_i), .out_o(chain_gated)
);
assign chain_en       = prop_carry_i;
assign chain_acc_i[0] = chain_gated[0];
assign chain_tap_i[0] = chain_gated[1];
assign chain_tap_i[1] = chain_gated[2];
```

This H→L fill bus runs **alongside** the existing L→H adder-carry chain (the `lane_cin` gate on the even lane): one control (`prop_carry_i`), two crossing buses, opposite directions. A fused pair is guaranteed equal exponents on both lanes — both read the same tap node, and, seeded consistently, hold equal registered scales — so the pair-shared scale needs no extra logic.

### The running scale register

The CPR 3:2 → `add_n` → mantissa register path is the baseline's. Beside it, a second `reg_n` holds the running accumulator scale — loaded with `align_exp` every cycle, reset to the minimum scale `0` — and drives `pe_exp_o`:

```systemverilog
assign red[0] = align_exp;
reg_n #(.WIDTH(EXP_WIDTH), .SIZE(1)) reg_n_exp_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(red), .q_o(req)
);
assign reg_exp_q[g] = req[0];
```

Because the scale only ever rises to a `max`, it is a **running max** within a run: a fed-back partial re-aligns (one right-shift, ≤ 1 ulp) when an incoming tap outranks it, and a tap floors when the accumulator outranks it — truncate only, LSB side, no rounding in the loop. The mantissa `pe_out_o` and the scale `pe_exp_o` leave un-normalized; `pe_exp_o` is already in the seed's product-domain format, so an output can loop straight back as a seed.

## Verification

[tb_acc_array_bfp](../../tb/tb_acc_array_bfp.sv) drives the full BFP chain (`disp_array{,_exp}_*` → [pe_array_bfp](./pe_array_bfp.md) → `acc_array_bfp`) with the integer chain alongside. **Pass A (equal exponents)** is bit-identical to the baseline `acc_array` — single-shot and seed/feedback accumulation — with exact exponents. **Pass B (distinct exponents, min-scale seed)** checks the accumulator bit-exact against `(seed >>> tap_exp) + N·tap` read from the BFP tap, exercising the aligner, the running-max register and the fused fill chain. 0 mismatches, `-Wall` clean.

Source: [acc_array_bfp.sv](../../rtl/acc_array_bfp.sv) — Testbench: [tb_acc_array_bfp.sv](../../tb/tb_acc_array_bfp.sv) — Diagram: [acc_array_bfp](../../doc/diagrams/acc_array_bfp.excalidraw)
