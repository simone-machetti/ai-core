# PE Testbench

## Purpose

`tb_top_pe_bas` verifies the whole PE, [top_pe_bas](../architectures/top_pe_bas.md), driven **only** by its external interface — the two operands, `mode_i`, `sel_acc_i` and `acc_i`. Because none of the internal `sel_*` / `ctr_*` controls are driven by the tb, a passing run proves not just the datapath but also that [pe_ctrl](../modules/pe_ctrl.md) decodes `mode_i` into the right controls and that `top_pe_bas` delays each of them to the correct pipeline cycle. Each of the 11 modes is checked at `pe_out` as a plain matrix multiply `X = A · B`, reusing the independent golden model from `tb_pe_array`. Lanes are corner-biased so the sign-consistency corners are reached.

## Parameters

| Parameter  | Default | Description                                                   |
| ---------- | ------- | ------------------------------------------------------------- |
| `NUM_RAND` | `2000`  | Number of random `A`,`B` matrix pairs per mode (single-shot). |
| `NUM_ACC`  | `8`     | Iterations in the accumulation pass.                          |

The DUT is instantiated with its defaults; the tb pins only the external shapes (operand width 256, `MODE_WIDTH = 4`, lane width `ACC_W = 20`, matmul bounds).

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_pe_bas PARAMS="NUM_RAND=2000"
```

## What it checks

| Aspect       | Detail                                                                                                                     |
| ------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Modes        | all 11 (8 real + 3 complex: 10, 11, 12), selected only through `mode_i`                                                    |
| Decode       | every internal control is produced by `pe_ctrl` from `mode_i` — a wrong row surfaces as a mismatch                         |
| Alignment    | a wrong per-stage control delay in `top_pe_bas` misaligns a control with its data — also a mismatch                            |
| Single-shot  | with `acc_i = 0`, `pe_out` equals the golden `A·B` reconstructed from the result's lane(s)                                 |
| Accumulation | seed `acc_i`, fold once (`sel_acc = 0`), accumulate `NUM_ACC-1` times (`sel_acc = 1`); `pe_out == seed + NUM_ACC · result` |
| Fusion       | wide results are read as `{pe_out[even], pe_out[odd]}` (40-bit H:L), exercising the carry chain                            |

## How it checks

### Reusing the pe_array golden

The mode tables (`MODE_NUM`, `TAP_LEVEL`), corner-biased stimulus (`rand_signed`), symmetric imaginary-B draw (`rand_signed_sym`), Storage-table packing, the independent `golden` matmul, and the `read_result` lane reconstruction are inherited unchanged from `tb_acc_array`. The only difference is the drive: instead of setting each `sel_*` / `ctr_*`, the tb writes `mode = MODE_NUM[mode]` and lets `pe_ctrl` derive them.

### Single-shot pass

Each vector packs a fresh matmul input, drives `mode_i`, waits three clock edges (`disp` → `pe_array` L0 register → `acc_array` register), then compares every result via `read_result` against the golden `X_re`/`X_im`. `acc_i` is held at 0 and `sel_acc = 0`, so `pe_out` is the plain resolved matmul.

### Accumulation pass

For each mode the tb holds a fixed input, writes a small external seed into the result's lane(s) with `set_acc`, folds it once (`sel_acc = 0`), then accumulates `NUM_ACC-1` times via feedback (`sel_acc = 1`), and checks `pe_out == seed + NUM_ACC · result`. Because `sel_acc` and `acc_i` are pipelined two cycles inside `top_pe_bas`, they are driven in the same issue time-base as the operands, and a `#1` after the first edge keeps the `sel_acc` `0→1` transition off the clock edge so the register update does not race the load:

```systemverilog
sel_acc = 1'b0;
@(posedge clk_i);
#1;
for (int it = 1; it < NUM_ACC; it++) begin
    sel_acc = 1'b1;
    @(posedge clk_i);
end
repeat (2) @(posedge clk_i);
```

### Reporting

Errors accumulate in `err`. Each mode prints `PASS` / `FAIL` for both passes; the run ends with `top_pe_bas verification: M/11 single-shot modes passed (E total mismatches)` — a clean run reports `11/11 ... 0 total mismatches` and every `acc mode N: PASS`.

Source: [tb_top_pe_bas.sv](../../tb/tb_top_pe_bas.sv) — DUT: [top_pe_bas](../architectures/top_pe_bas.md)
