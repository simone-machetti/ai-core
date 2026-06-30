# A-magnitude sweep at fixed B = 127 (normal distribution)

Power characterization of four 4×8 PE architectures while sweeping `MAX_VAL_A` across {0, 1, 2, 3, 4, 5, 6, 7} with random sign per cycle, at fixed `MAX_VAL_B = 127` and `DIST_TYPE = 1` (normal). The synthesis directories are reused from [dyn_range](../dyn_range/README.md) (`<slug>_dyn_syn`), since `MAX_VAL_*` is testbench-only and does not affect the netlist.

## Sweep parameters

| Knob            | Value(s)                               |
|-----------------|----------------------------------------|
| `MAX_VAL_A`     | {0, 1, 2, 3, 4, 5, 6, 7}               |
| `MAX_VAL_B`     | 127 (fixed)                            |
| `DIST_TYPE`     | 1 (normal)                             |
| `MU_SCALE`      | 7/8 (flow override; TB default is 1/2) |
| `SIGMA_SCALE`   | 1/8 (flow override; TB default is 1/6) |
| `CLK_PERIOD_NS` | 1.35                                   |

With these overrides, for B the Gaussian has μ ≈ 111.1 and σ ≈ 15.9 (true Gaussian spread). For A at `MAX_VAL_A ≤ 7` the Gaussian has σ < 1 lsb, so values are quantized to ±`MAX_VAL_A` with random sign — equivalent to "fixed magnitude with random sign". At `MAX_VAL_A = 0`, `gen_a` returns 0 unconditionally (no sign).

## Architectures under test

| Slug                | Top-level              | `IS_PIPELINED` | Other params           | Has B? |
|---------------------|------------------------|----------------|------------------------|--------|
| `bas_4x8`           | `top_bas_4x8`          | 1              | `MULT_TYPE=0`          | yes    |
| `sqr_4x8_sc`        | `top_sqr_4x8_sc`       | 1              | `SQR_TYPE=0` (default) | yes    |
| `sqr_4x8_alpha_sum` | `top_sqr_4x8_sc_alpha` | **0**          | `IS_SQUARE=0`          | no     |
| `sqr_4x8_alpha_sqr` | `top_sqr_4x8_sc_alpha` | **0**          | `IS_SQUARE=1`          | no     |

The alpha variants are intentionally non-pipelined.

## Run matrix

| Slug                | Points |
|---------------------|-------:|
| `bas_4x8`           |      8 |
| `sqr_4x8_sc`        |      8 |
| `sqr_4x8_alpha_sum` |      8 |
| `sqr_4x8_alpha_sqr` |      8 |
| **Total**           | **32** |

For each (slug, A) tuple:

1. `make post-syn-sim` → gate-level sim with the (A, B=127) inputs; produces `activity.vcd`.
2. `make post-syn-dpa` → OpenSTA power analysis; produces `report/power_summary.rpt`.

## Directory naming

| Artifact           | Path                                                                  |
|--------------------|-----------------------------------------------------------------------|
| Synthesis (reused) | `imp/<slug>_dyn_syn/`                                                 |
| Post-syn-sim       | `sim/<slug>_asw_a<A>_b127_post_syn_sim/` (`_b127` omitted for alphas) |
| Post-syn-DPA       | `imp/<slug>_asw_a<A>_b127_dpa/` (`_b127` omitted for alphas)          |

## Outputs

- `doc/data/a_sweep/results.xlsx` — eight sheets:
  - `power_bas_4x8`, `power_sqr_4x8_sc`, `power_alpha_sum`, `power_alpha_sqr` — single-column power tables in µW, indexed by A
  - `config_1` — Square vs Baseline, PE arms only
  - `config_2` — Square vs Baseline, with both alpha arms
  - `config_3` — Square vs Baseline, reduced-array variant (8×8)
  - `config_4` — Square vs Baseline, full-array split alpha lanes (8×16)
- `doc/charts/a_sweep/config_1.png` … `config_4.png` — 1-D heatmap row (one cell per A) of the improvement (%) for each configuration
- `doc/charts/a_sweep/improvement.png` — all four configurations overlaid as a line plot vs `MAX_VAL_A`

All power values are total dynamic + leakage from OpenSTA, in µW.

## Configurations

Each configuration applies different multipliers to the per-cell power numbers to model a different array topology. The improvement is `100 × (Baseline_total − Square_total) / Baseline_total` and a positive value means Square is more efficient.

### config_1 — PE arms only (4×8 baseline)

```
Baseline_total(A) = bas_4x8(A, 127) × 256
Square_total(A)   = sqr_4x8_alpha_sqr(A) × 64
                  + sqr_4x8_sc(A, 127) × 256
```

### config_2 — with both alpha arms (4×8 full)

```
Baseline_total(A) = bas_4x8(A, 127) × 256
Square_total(A)   = sqr_4x8_alpha_sqr(A) × 64
                  + sqr_4x8_alpha_sum(A) × 48
                  + sqr_4x8_sc(A, 127) × 256
```

### config_3 — reduced-array variant (8×8 PE array)

```
Baseline_total(A) = bas_4x8(A, 127) × 64
Square_total(A)   = sqr_4x8_sc(A, 127) × 64
                  + sqr_4x8_alpha_sqr(A) × 32
                  + sqr_4x8_alpha_sum(A) × 24
```

### config_4 — full-array split alpha lanes (8×16 PE array)

```
Baseline_total(A) = bas_4x8(A, 127) × 128
Square_total(A)   = sqr_4x8_sc(A, 127) × 128
                  + sqr_4x8_alpha_sqr(A) × 48
                  + sqr_4x8_alpha_sum(A) × 40
```

## How to run

```bash
source sourceme.sh
python3 scripts/flow/a_sweep/run.py # 32 sim + DPA points (idempotent)
python3 scripts/flow/a_sweep/ext.py # imp/ → doc/data/a_sweep/results.xlsx
python3 scripts/flow/a_sweep/gen.py # → doc/charts/a_sweep/{config_1..4,improvement}.png
```
