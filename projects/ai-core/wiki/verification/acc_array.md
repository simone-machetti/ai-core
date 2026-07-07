# Accumulator Array Testbench

## Purpose

`tb_acc_array` verifies the full PE datapath `disp_array → pe_array → acc_array` end to end. Each of the 11 modes is checked at `pe_out` as a plain matrix multiply `X = A · B`, using the independent golden model from `tb_pe_array` (which knows nothing about the tree, crossover, shifts, windowing, or fusion), so a bug anywhere in the chain — including `acc_array`'s tap select, window split, resolve, or carry chain — surfaces as a mismatch. Lanes are corner-biased so the sign-consistency corners are reached.

## Parameters

| Parameter  | Default | Description                                                   |
| ---------- | ------- | ------------------------------------------------------------- |
| `NUM_RAND` | `2000`  | Number of random `A`,`B` matrix pairs per mode (single-shot). |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass.                          |

The three DUTs are instantiated with their defaults; the tb pins the shapes (`NUM_DP8 = 16`, tap widths `18/29/37/38`, lane width `ACC_W = 20`, matmul bounds) and does not override any DUT parameter.

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=acc_array PARAMS="NUM_RAND=2000"
```

## What it checks

| Aspect        | Detail                                                                                                       |
| ------------- | ------------------------------------------------------------------------------------------------------------ |
| Modes         | all 11 (8 real + 3 complex: 10, 11, 12)                                                                      |
| Single-shot   | with `acc_i = 0`, `pe_out` equals the golden `A·B` reconstructed from the result's lane(s)                   |
| Accumulation  | load an external seed, then feedback-accumulate `NUM_ACC-1` times; `pe_out` equals `seed + NUM_ACC · result` |
| Fusion        | wide results are read as `{pe_out[even], pe_out[odd]}` (40-bit H:L), exercising the inter-lane carry chain   |
| External word | the accumulation pass seeds via `acc_i` (`sel_acc = 0`), covering the external-accumulator fold              |

## How it checks

### Reusing the pe_array golden

The mode tables, corner-biased stimulus (`rand_signed`), symmetric imaginary-B draw (`rand_signed_sym`), Storage-table packing, and the independent `golden` matmul are inherited unchanged from `tb_pe_array`. Only the readout and the drive of `acc_array`'s controls are new. `set_controls` additionally drives the accumulator shape: `sel_out = TAP_LEVEL[mode]` and `prop_carry = (TAP_LEVEL ≥ 1)` (fuse for L1/L2/L3, standalone for L0).

### Reading a result from pe_out

`read_result` maps a result's `(level, node)` to its lane(s) and reconstructs the value — one lane at L0, or the `{H(even), L(odd)}` 40-bit pair at L1/L2/L3:

```systemverilog
if (lvl == 0) return longint'($signed(pe_out[node]));
...
return longint'($signed({pe_out[hlane], pe_out[llane]}));
```

### Single-shot pass

Each vector packs a fresh matmul input, waits three clock edges (`disp` → `pe_array` L0 register → `acc_array` register), then compares every result via `read_result` against the golden `X_re`/`X_im`. `acc_i` is held at 0 and `sel_acc = 0`, so `pe_out` is the plain resolved matmul.

### Accumulation pass

For each mode the tb holds a fixed input, writes a small external seed into the result's lane(s) with `set_acc`, folds it once (`sel_acc = 0`), then accumulates `NUM_ACC-1` times via feedback (`sel_acc = 1`), and checks `pe_out == seed + NUM_ACC · result`. A `#1` after the flush separates the `sel_acc` change from the clock edge so the load is not raced by the register update:

```systemverilog
sel_acc = 1'b0;
repeat (3) @(posedge clk_i);
#1;
for (int it = 1; it < NUM_ACC; it++) begin
    sel_acc = 1'b1;
    @(posedge clk_i);
end
```

### Reporting

Errors accumulate in `err`. Each mode prints `PASS` / `FAIL` for both passes; the run ends with `acc_array verification: M/11 single-shot modes passed (E total mismatches)` — a clean run reports `11/11 ... 0 total mismatches` and every `acc mode N: PASS`.

Source: [tb_acc_array.sv](../../tb/tb_acc_array.sv) — DUT: [acc_array](../architecture/acc_array.md)
