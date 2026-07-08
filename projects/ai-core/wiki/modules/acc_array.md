# Accumulator Array

`acc_array` — the final PE stage: eight 20-bit accumulation lanes that read the carry-save taps of [pe_array](./pe_array.md), resolve the tap a mode selects into a binary value, optionally accumulate it, and drive eight `pe_out` outputs.

## Purpose

Each of `pe_array`'s taps is a redundant carry-save pair `(sum, carry)`. `acc_array` turns the pair the mode reads into a real binary number, adds it to a running or external accumulator, and outputs it. A result up to 20 bits lives in one lane; a wider result (up to 40 bits) is split across a **lane pair** — the even lane holds the high half, the odd lane the low half — with a carry chained between them, so two 20-bit lanes fuse into one 40-bit result. The array is fixed to the PE; its four data-path primitives ([mux_n](./mux_n.md), [cpr_w_n](./cpr_w_n.md), [add_n](./add_n.md), [gate_n](./gate_n.md), plus [reg_n](./reg_n.md)) are reused as-is.

## Parameters

None — fixed to the PE configuration; the shape is baked in as `localparam`s. The key ones:

| Localparam            | Value             | Meaning                                                          |
| --------------------- | ----------------- | ---------------------------------------------------------------- |
| `NUM_LANE`            | 8                 | Accumulation lanes (one per output).                             |
| `PE_WIDTH`            | 20                | Per-lane / `pe_out` width.                                       |
| `FUSE`                | 40                | Sign-extended tap width used for windowing.                      |
| `CPR_WIDTH`           | 22                | CPR 3:2 / `add_n` width (`PE_WIDTH + 2`; holds the 2-bit carry). |
| `CARRY`               | 2                 | Inter-lane carry width.                                          |
| `L0_WIDTH`…`L3_WIDTH` | 18 / 29 / 37 / 38 | `pe_array` tap widths (carry-save pairs).                        |
| `SEL_WIDTH`           | 2                 | Tap-level select: L0 / L1 / L2 / L3.                             |

## Interface

| Signal                       | Dir | Width   | Description                                                         |
| ---------------------------- | --- | ------- | ------------------------------------------------------------------- |
| `clk_i`                      | in  | 1       | Clock.                                                              |
| `rst_ni`                     | in  | 1       | Asynchronous active-low reset.                                      |
| `l0_sum_i`/`l0_carry_i[0:7]` | in  | 18 each | L0 tap pairs, from `pe_array`.                                      |
| `l1_sum_i`/`l1_carry_i[0:3]` | in  | 29 each | L1 tap pairs.                                                       |
| `l2_sum_i`/`l2_carry_i[0:1]` | in  | 37 each | L2 tap pairs.                                                       |
| `l3_sum_i`/`l3_carry_i`      | in  | 38      | L3 tap pair.                                                        |
| `acc_i[0:7]`                 | in  | 20 each | External accumulator word, one per lane.                            |
| `sel_out_i`                  | in  | 2       | Tap-level select (shared): which tree level all lanes read.         |
| `sel_acc_i`                  | in  | 1       | Accumulate MUX (shared): `0` = `acc_i[k]`, `1` = register feedback. |
| `prop_carry_i`               | in  | 1       | Inter-lane carry-chain enable (shared): lane fusion.                |
| `pe_out_o[0:7]`              | out | 20 each | Per-lane results; a fused result is `{pe_out[even], pe_out[odd]}`.  |

## Instantiation

```systemverilog
acc_array acc_array_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .l0_sum_i(l0_sum), .l0_carry_i(l0_carry),
    .l1_sum_i(l1_sum), .l1_carry_i(l1_carry),
    .l2_sum_i(l2_sum), .l2_carry_i(l2_carry),
    .l3_sum_i(l3_sum), .l3_carry_i(l3_carry),
    .acc_i(acc_word),
    .sel_out_i(sel_out), .sel_acc_i(sel_acc), .prop_carry_i(prop_carry),
    .pe_out_o(pe_out)
);
```

## Internal logic

The datapath, per lane, is: **window the taps → tap-level MUX → CPR 3:2 (with the accumulate MUX) → add_n → register**, with a 2-bit carry chained between paired lanes. Everything is built inside one per-lane generate loop. Instance counts: 16 `mux_n` (2 per lane), 8 `cpr_w_n` (3:2), 8 `add_n`, 4 `gate_n` (one per even/high lane), 8 `reg_n` (one per lane).

### Windowing the taps

Each tap `(sum, carry)` is sign-extended to 40 bits, then split into a low window `[19:0]` and a high window `[39:20]`. A lane takes the **H** window if it is even, the **L** window if it is odd; L0 taps hold a ≤16-bit value and use the low window directly (single-lane, no fusion):

```systemverilog
assign l1s = FUSE'($signed(l1_sum_i[g/2]));
assign l1c = FUSE'($signed(l1_carry_i[g/2]));
if (g % 2 == 0) begin : gen_l1_h
    assign w_sum[g][1] = l1s[FUSE-1:PE_WIDTH];   // high 20
    assign w_car[g][1] = l1c[FUSE-1:PE_WIDTH];
end else begin : gen_l1_l
    assign w_sum[g][1] = l1s[PE_WIDTH-1:0];      // low 20
    assign w_car[g][1] = l1c[PE_WIDTH-1:0];
end
```

Sign-extending to the full 40-bit width **before** slicing is what makes the split correct: each window is then a plain unsigned slice, the sign lives in the top window's MSB, and carry-chaining the windows reconstructs the true signed value. This relies on the tap pair being **sign-consistent** (`signext(sum) + signext(carry)` = value), which is exactly what `pe_array` guarantees. Not every lane sees every level — L2 exists only for lanes 2, 3, 6, 7 and L3 only for lanes 6, 7; the missing levels are tied to `'0` (that lane is unused for those modes).

### Tap → lane wiring

A wide node's H half goes to the even lane, its L half to the odd lane; L1/L2/L3 span a lane pair, L0 is one lane:

| Lane | L0      | L1       | L2       | L3       |
| ---- | ------- | -------- | -------- | -------- |
| 0    | `l0[0]` | `l1[0]H` | —        | —        |
| 1    | `l0[1]` | `l1[0]L` | —        | —        |
| 2    | `l0[2]` | `l1[1]H` | `l2[0]H` | —        |
| 3    | `l0[3]` | `l1[1]L` | `l2[0]L` | —        |
| 4    | `l0[4]` | `l1[2]H` | —        | —        |
| 5    | `l0[5]` | `l1[2]L` | —        | —        |
| 6    | `l0[6]` | `l1[3]H` | `l2[1]H` | `l3[0]H` |
| 7    | `l0[7]` | `l1[3]L` | `l2[1]L` | `l3[0]L` |

### Tap-level and accumulate MUXes

A `mux_n` per lane selects the level's `(sum, carry)` window pair (packed into one 40-bit word) with the shared `sel_out_i`. A second `mux_n` selects the third CPR row — the external accumulator word `acc_i[k]` or the lane's register feedback — with the shared `sel_acc_i`:

```systemverilog
assign accmux_in[0] = acc_i[g];     // sel_acc = 0
assign accmux_in[1] = reg_q[g];     // sel_acc = 1
mux_n #(.WIDTH(PE_WIDTH), .SIZE(2)) acc_mux_i (
    .in_i(accmux_in), .sel_i(sel_acc_i), .out_o(acc_sel)
);
```

### CPR 3:2 and the 2-bit carry

Each lane folds three 20-bit rows — `tap_sum`, `tap_carry`, and the selected accumulator — with a `cpr_w_n` 3:2. Three 20-bit rows can overflow bit 19 by up to **2 bits**, so the compressor keeps two guard bits (`EXT = 2`, 22-bit rows) so no carry is lost, and it runs unsigned (the sign was handled upstream by the 40-bit extension):

```systemverilog
cpr_w_n #(.IN_WIDTH(PE_WIDTH), .IN_SIZE(3), .EXT(2), .IS_SIGNED(1'b0)) cpr_w_n_i (
    .in_i(cpr_in), .sum_o(cpr_sum), .carry_o(cpr_car)
);
```

### Resolve and window split

`add_n` resolves the two 22-bit CPR rows plus the 2-bit carry-in and hands back the split directly — `out_o` is the 20-bit window value (straight to the register), `cout_o` is the 2-bit carry-out to the paired lane:

```systemverilog
add_n #(.WIDTH(PE_WIDTH), .CARRY(CARRY)) add_n_i (
    .in_0_i(cpr_sum), .in_1_i(cpr_car), .cin_i(lane_cin[g]),
    .out_o(rd[0]), .cout_o(lane_carry[g])
);
```

`add_n` adds two `WIDTH+CARRY`-bit operands (the 22-bit CPR rows) and presents `out_o` as the low 20 bits and `cout_o` as the top 2 — no slicing or unused bits in `acc_array`.

### The carry chain

Each even (high) lane instantiates a `gate_n #(.WIDTH(CARRY), .SIZE(1))` that gates its odd partner's carry; the odd lanes take no carry-in, and a standalone (L0) mode leaves `prop_carry_i = 0` so the lanes stay independent:

```systemverilog
if (g % 2 == 0) begin : gen_carry
    assign cin_in[0] = lane_carry[g+1];
    gate_n #(.WIDTH(CARRY), .SIZE(1)) gate_n_i (
        .in_i(cin_in), .sel_i(~prop_carry_i), .out_o(cin_out)
    );
    assign lane_cin[g] = cin_out[0];
end else begin : gen_no_carry
    assign lane_cin[g] = '0;
end
```

The two carry bits share weight `2^20` (bit 0 of the high window), so the high lane simply adds the 0–2 carry at its least-significant end.

### The register

Each lane instantiates its own `reg_n #(.WIDTH(PE_WIDTH), .SIZE(1))` holding that lane's result; the output feeds `pe_out_o` and loops back as the accumulate MUX's feedback input, so a lane can accumulate across cycles. `reg_q → acc MUX → CPR → add_n → reg` is combinational within a cycle; the register breaks the loop.

### Using it: single-shot vs. accumulate

- **Single-shot output:** `sel_acc = 0` with `acc_i[k] = 0` folds a zero third row, so `pe_out` is just the resolved matmul result.
- **External accumulate:** `sel_acc = 0` with a non-zero `acc_i[k]` adds an externally-provided value (bias, or a running sum held in memory) to the new partial.
- **Feedback accumulate:** `sel_acc = 1` folds the register back in, so `pe_out` grows by the new partial each cycle.

Verified end to end (`disp_array → pe_array → acc_array`) across all 11 modes, both single-shot and accumulating.

Source: [acc_array.sv](../../rtl/acc_array.sv) — Testbench: [tb_acc_array.sv](../../tb/tb_acc_array.sv) — Diagram: [acc_array](../../doc/diagrams/acc_array.excalidraw)
