# PE Grid Testbench

## Purpose

`tb_top_NxN_bas` verifies the N × N PE grid [top_NxN_bas](../architectures/top_NxN_bas.md) through its grid interface only — per-row A, per-col B, shared `mode`/`sel_acc`, per-PE `acc` and `clk_gate` — checking each PE at its own `out_q`. Operands are **distinct per PE**: it draws `N` independent corner-biased A matrices (one per row) and `N` independent B matrices (one per column), so PE[r][c] evaluates `A[r] · B[c]` and any wrong row/column fan-out surfaces as a mismatch. The per-PE golden reuses the mode tables, packing, and result reconstruction of the single-PE testbench.

## Parameters

| Parameter  | Default | Description                                                               |
| ---------- | ------- | ------------------------------------------------------------------------- |
| `N`        | `2`     | Grid side; the array is `N × N` PEs (small default keeps the build fast). |
| `NUM_RAND` | `1`     | Random draws per mode for the one-shot pass and each clock-gate case.     |
| `NUM_ACC`  | `3`     | Iterations in the accumulation pass.                                      |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=top_NxN_bas PARAMS="N=2 NUM_RAND=1 NUM_ACC=3"
```

Larger arrays cost far more to build, so bump `N` deliberately (e.g. `PARAMS="N=8"` for the full chip). Tracing is off by default; add `VCD=1` for a waveform.

## What it checks

| Aspect       | Detail                                                                                                                  |
| ------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Fan-out      | distinct A per row, B per col; every PE must equal `golden(A[row] · B[col])`, so a mis-routed operand mismatches        |
| Modes        | all 11 (8 real + 3 complex), selected through the shared `mode`                                                         |
| One-shot     | `sel_acc = 0`, `acc = 0`, no gating; each PE `out_q == golden(A[r]·B[c])`                                               |
| Accumulation | per-PE seed via `acc`, shared `sel_acc` runs `NUM_ACC` iterations; `out_q == seed + NUM_ACC · golden`                   |
| Clock gating | gate a quarter / half / three-quarters / all of the PEs; the gated ones stay `0` (clock stopped) while the rest compute |

## How it checks

The tb draws and stores the `N` per-row A and `N` per-col B matrices (`gen_operands`), packs each into its operand word (`pack_a` → `in_a[r]`, `pack_b` → `in_b[c]`), and evaluates the golden per pair (`eval_pe` copies row `A` and col `B` into the working matrices, then runs the shared `golden`). `check_pe` then compares that PE's `out_q` — read back through the same lane / fused `{H, L}` reconstruction as the single-PE testbench.

Three passes run in sequence, **with a reset between experiment types**:

1. **One-shot** — present the grid operands, wait the 3-cycle latency, check every PE.
2. **Accumulation** — seed each PE via `acc`, then the shared `sel_acc` sequence (load, then feedback, with a `#1` off the clock edge so the load is not raced) accumulates in lockstep across the whole array; check `seed + NUM_ACC · golden` per PE.
3. **Clock gating** — for each gate fraction: reset (so `out_q = 0`), gate the first `k` PEs by flat index, present operands, and check the gated PEs held `0` (proving the ICG stopped their clock) while the ungated PEs computed golden. With all PEs gated, nothing updates.

Each mode prints `PASS` / `FAIL` per pass; a clean run reports `top_NxN_bas verification: 11/11 one-shot modes passed (0 total mismatches)` with every `acc mode` and `gate mode` also `PASS`.

Source: [tb_top_NxN_bas.sv](../../tb/tb_top_NxN_bas.sv) — DUT: [top_NxN_bas](../architectures/top_NxN_bas.md)
