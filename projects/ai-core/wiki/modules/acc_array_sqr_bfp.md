# Accumulator Array (Square-BFP)

`acc_array_sqr_bfp` — the final stage of the **square-BFP** PE. It is [acc_array_bfp](./acc_array_bfp.md) (per-lane [align_cell_bfp](./align_cell_bfp.md), running-max exponent register, seed ≡ feedback format, lane-fusion align chain, `L→H` adder carry) **plus** the square's `½`, borrowed verbatim from [acc_array_sqr](./acc_array_sqr.md): a `<<1` on the acc row entering the fold and an arithmetic `>>1` on the resolved sum. Because [pe_array_sqr_bfp](./pe_array_sqr_bfp.md)'s tree already delivers `2·P` as one tap pair, there is a **single 2-row tap set** and **no `C`/`c_neg` ports** — the `PE − α − β + C` combine is folded per-DP8 at L0 upstream (see [BFP_imp.md](../../doc/BFP_imp.md) §9).

## Purpose

Where [acc_array_sqr](./acc_array_sqr.md) resolves the full square reconstruction (three tap sets + a per-mode constant) and `acc_array_bfp` adds the exponent machinery, this array is the **intersection**: the BFP aligner and running-max scale from the baseline, fed one already-combined product tap `2·P`, with the square's two shifts wrapped around the fold. The register holds the true running value `P + acc` at its BFP scale — `½(2·acc + 2·P) = acc + P`, exact because the resolved `2·P` is even when the exponents match. With all exponents equal the array is bit-identical to `acc_array_sqr` fed the same result.

Per lane (even lane = high half of a fused pair, odd = low; single-lane L0 when unfused):

- **Tap mux** ([mux_n](./mux_n.md), `sel_out_i`) selects the read level for the one operand → the `{sum,carry}` pair, windowed to 20-bit exactly as `acc_array_bfp` does (sign-extend the 40-bit tap; even lane = high half `[39:20]`, odd = low `[19:0]`), plus its exponent through a parallel `mux_n`.
- **Acc mux** ([mux_n](./mux_n.md), `sel_acc_i`) picks the external seed `acc_i` or the register feedback — **value and exponent together**, since seed and feedback share one format.
- **`×2`** (`acc_x2`, `<<1` on the acc-mux output) makes the accumulated term enter the fold at 2×, keeping `acc_i`/`pe_out` in native units. For a fused pair the low lane's shifted-out MSB fills the high lane's LSB through [gate_n](./gate_n.md) (`gate_n_mul_2_i`, `sel = ~fused`); the odd (low) lane shifts in `0`.
- **Align** ([align_cell_bfp](./align_cell_bfp.md), `SIZE_0=1`, `SIZE_1=2`) brings the acc row (group 0, `acc_exp_sel`) and the tap pair (group 1, `tap_exp`) to `max(acc_exp, tap_exp)`, emitting **3 rows** and the running-max `align_exp`. The lane-fusion align chain crosses odd→even through [gate_n](./gate_n.md) (`gate_n_align_i`, `sel = ~prop_carry_i`).
- **CPR 3:2** ([cpr_w_n](./cpr_w_n.md), `EXT=3`) folds the 3 aligned rows to two; **`add_n`** ([add_n](./add_n.md), `CARRY=3`) resolves them plus the inter-lane carry into the 20-bit window (`= 2·R_new`).
- **Inter-lane carry** ([gate_n](./gate_n.md), `gate_n_add_i`, `sel = ~prop_carry_i`) chains `L(odd) → H(even).cin` (3 bits — the `<<1` adds a bit of overflow over `acc_array_bfp`'s 2).
- **`÷2`** (`half`, arithmetic `>>1` before the register) applies the ½. The even (high) lane sign-fills; the odd (low) lane takes the high lane's shifted-out LSB on a fused output — an **inline ternary MUX** (arithmetic sign-fill), not a `gate_n`.
- **Register** ([reg_n](./reg_n.md) ×2) holds the true result `R_new` and its running scale `reg_exp_q` — no decay, no 2× register.

The two shifts:

```systemverilog
// x2: even (high) lane pulls in the low lane's shifted-out MSB, gated by fused
assign acc_x2[g] = {acc_sel[g][PE_WIDTH-2:0], msb_out[0]};   // odd lane: {acc_sel[g][PE_WIDTH-2:0], 1'b0}

// half (÷2): even lane sign-fills; odd lane takes the high lane's shifted-out LSB when fused
assign half[g] = {(fused ? rd[g-1][0] : rd[g][PE_WIDTH-1]), rd[g][PE_WIDTH-1:1]};
```

`fused = |sel_out_i` (any non-L0 read fuses lane pairs) gates the `<<1`/`>>1` cross-lane bits; `prop_carry_i` gates the align chain and the adder carry.

## Parameters

None — fixed to the PE configuration; the key `localparam`s:

| Localparam            | Value             | Meaning                                                     |
| --------------------- | ----------------- | ----------------------------------------------------------- |
| `NUM_LANE`            | 8                 | Accumulation lanes (one per output).                        |
| `PE_WIDTH`            | 20                | Per-lane / `pe_out` width (true result).                    |
| `FUSE`                | 40                | Sign-extended tap width used for windowing.                 |
| `EXP_WIDTH`           | 7                 | Product-domain scale `e_A + e_B` (seed ≡ feedback).         |
| `EXT` / `CARRY`       | 3 / 3             | CPR 3:2 guard bits / adder carry (the `<<1` adds one bit).  |
| `ROWS`                | 3                 | Rows into the CPR: acc row + tap `{sum,carry}`.             |
| `L0_WIDTH`…`L3_WIDTH` | 19 / 30 / 38 / 39 | Square-BFP tap widths (baseline-BFP + 1; they carry `2·P`). |
| `SEL_WIDTH`           | 2                 | Tap-level select.                                           |

## Interface

| Signal                             | Dir | Width   | Description                                                      |
| ---------------------------------- | --- | ------- | --------------------------------------------------------------- |
| `clk_i` / `rst_ni`                 | in  | 1       | Clock / async active-low reset.                                 |
| `l0_sum_i` / `l0_carry_i[0:7]`     | in  | 19 each | L0 tap pairs (`2·P`), from `pe_array_sqr_bfp`.                  |
| `l1_sum_i` / `l1_carry_i[0:3]`     | in  | 30 each | L1 tap pairs.                                                    |
| `l2_sum_i` / `l2_carry_i[0:1]`     | in  | 38 each | L2 tap pairs.                                                    |
| `l3_sum_i` / `l3_carry_i`          | in  | 39      | L3 tap pair (scalar).                                            |
| `l0_exp_i[0:7]` … `l3_exp_i`       | in  | 7 each  | Per-level tap exponents (product scale), from the tree.         |
| `acc_i[0:7]`                       | in  | 20 each | External seed, **native units** (the `<<1` doubles it inside).  |
| `acc_exp_i[0:7]`                   | in  | 7 each  | Seed exponent — same 7-bit product scale as the feedback.       |
| `sel_out_i`                        | in  | 2       | Tap-level select (shared): which tree level all lanes read.     |
| `sel_acc_i`                        | in  | 1       | Acc mux (shared): `0` = `acc_i`, `1` = register feedback.       |
| `prop_carry_i`                     | in  | 1       | Lane-fusion enable (shared): align chain + adder carry.         |
| `pe_out_o[0:7]`                    | out | 20 each | Per-lane running result `P + acc`, **native units**.            |
| `pe_exp_o[0:7]`                    | out | 7 each  | Per-lane running BFP scale (the max held by the register).      |

## Instantiation

```systemverilog
acc_array_sqr_bfp acc_array_sqr_bfp_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .l0_sum_i(l0_sum), .l0_carry_i(l0_carry), /* … l1/l2/l3 … */
    .l0_exp_i(l0_exp), .l1_exp_i(l1_exp), .l2_exp_i(l2_exp), .l3_exp_i(l3_exp),
    .acc_i(acc_q2), .acc_exp_i(acc_exp_q2),
    .sel_out_i(sel_out), .sel_acc_i(sel_acc), .prop_carry_i(prop_carry),
    .pe_out_o(out), .pe_exp_o(out_exp)
);
```

## Verification

[tb_acc_array_sqr_bfp](../../tb/tb_acc_array_sqr_bfp.sv) wires the whole square-BFP path three ways and checks against a matmul golden `X = A·B`. **Pass A (equal exponents)** proves `matmul === sqr(pe_out) === sqr_bfp(pe_out)` single-shot and across accumulation (`seed + NUM_ACC·X`), exercising `acc_x2`/`half`, the fused cross-lane bits and the running-max scale with no rounding. **Pass B (distinct exponents, min-scale seed)** checks the BFP output against its own tap — `((2·seed >>> e) + 2P) >>> 1 + (NUM_ACC−1)·(2P >>> 1)` and `pe_exp === e` — the finer per-tap distinct-exp check. 11/11 modes, corner-biased operands, 0 mismatches, confirming no `C`/`c_neg` at the accumulator and the `EXT=CARRY=3` ½ path.

Source: [acc_array_sqr_bfp.sv](../../rtl/acc_array_sqr_bfp.sv) — Testbench: [tb_acc_array_sqr_bfp.sv](../../tb/tb_acc_array_sqr_bfp.sv) — Diagram: [acc_array_sqr_bfp](../../doc/diagrams/acc_array_sqr_bfp.excalidraw)
