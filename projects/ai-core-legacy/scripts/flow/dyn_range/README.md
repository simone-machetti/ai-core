# Dynamic-range power sweep (normal distribution)

Power characterization of four 4×8 PE architectures across a 2-D sweep of the input dynamic range, using the `DIST_TYPE=1` (normal, tight cluster near the chosen max value) input distribution.

## Sweep parameters

| Knob            | Values                            | Steps                                    |
|-----------------|-----------------------------------|------------------------------------------|
| `MAX_VAL_A`     | {1, 3, 5, 7}                      | 4 (linear, stride 2)                     |
| `MAX_VAL_B`     | {1, 19, 37, 55, 73, 91, 109, 127} | 8 (linear, stride 18)                    |
| `DIST_TYPE`     | 1 (normal)                        | fixed                                    |
| `MU_SCALE`      | 7/8                               | fixed (flow override; TB default is 1/2) |
| `SIGMA_SCALE`   | 1/8                               | fixed (flow override; TB default is 1/6) |
| `CLK_PERIOD_NS` | 1.35                              | fixed                                    |

With these overrides, the normal distribution at each point has μ = `7/8 × MAX_VAL` and σ = `1/8 × MAX_VAL`, then randomly negated — values cluster tightly around ±`MAX_VAL`.

## Architectures under test

| Slug                | Top-level              | `IS_PIPELINED` | Other params           | Has B? |
|---------------------|------------------------|----------------|------------------------|--------|
| `bas_4x8`           | `top_bas_4x8`          | 1              | `MULT_TYPE=0`          | yes    |
| `sqr_4x8_sc`        | `top_sqr_4x8_sc`       | 1              | `SQR_TYPE=0` (default) | yes    |
| `sqr_4x8_alpha_sum` | `top_sqr_4x8_sc_alpha` | **0**          | `IS_SQUARE=0`          | no     |
| `sqr_4x8_alpha_sqr` | `top_sqr_4x8_sc_alpha` | **0**          | `IS_SQUARE=1`          | no     |

The two alpha variants are intentionally non-pipelined (2-cycle), since they are used as the "broadcast" arms of the squaring expansion.

## Run matrix

| Slug                |     Points |
|---------------------|-----------:|
| `bas_4x8`           | 4 × 8 = 32 |
| `sqr_4x8_sc`        | 4 × 8 = 32 |
| `sqr_4x8_alpha_sum` |          4 |
| `sqr_4x8_alpha_sqr` |          4 |
| **Total**           |     **72** |

Synthesis runs **once per architecture** (4 builds total); `MAX_VAL_*` is a testbench-only parameter and does not affect the netlist.

## Flow per point

For each (slug, A, B) tuple:

1. `make post-syn-sim` — gate-level simulation; produces `activity.vcd`.
2. `make post-syn-dpa` — OpenSTA power analysis; produces `report/power_summary.rpt`. Total power is the `Total` line, 5th column (Watts).

## Directory naming

| Artifact     | Path                                     |
|--------------|------------------------------------------|
| Synthesis    | `imp/<slug>_dyn_syn/`                    |
| Post-syn-sim | `sim/<slug>_dyn_a<A>_b<B>_post_syn_sim/` |
| Post-syn-DPA | `imp/<slug>_dyn_a<A>_b<B>_dpa/`          |

For alpha variants the suffix is `_dyn_a<A>_…` (no `_b<B>`).

## Outputs

- `doc/data/dyn_range/results.xlsx` — eight sheets:
  - `power_bas_4x8`, `power_sqr_4x8_sc` — 2-D tables (rows = A, cols = B), µW
  - `power_alpha_sum`, `power_alpha_sqr` — 1-D tables (rows = A), µW
  - `config_1` — Square vs Baseline (%), PE arms only
  - `config_2` — Square vs Baseline (%), with both alpha arms (default scenario for charts)
  - `config_3` — Square vs Baseline (%), reduced-array variant (8×8)
  - `config_4` — Square vs Baseline (%), full-array split alpha lanes (8×16)
- `doc/charts/dyn_range/config_2.png` — heatmap of `config_2`
- `doc/charts/dyn_range/config_3.png` — heatmap of `config_3`
- `doc/charts/dyn_range/config_4.png` — heatmap of `config_4`
- `doc/charts/dyn_range/config_2_abs.png` — heatmap of absolute (mW) saving for `config_2`
- `doc/charts/dyn_range/config_2_abs_lines.png` — line plot of absolute (mW) saving for `config_2`
- `doc/charts/dyn_range/config_2_3d.png` — 3-D bar chart of absolute (mW) saving for `config_2`

All power values are total dynamic + leakage power from OpenSTA, in **µW**.

## Configurations

Each configuration applies different multipliers to the per-cell power numbers to model a different array topology. The improvement is `100 × (Baseline_total − Square_total) / Baseline_total` and a positive value means Square is more efficient.

### config_1 — PE arms only (4×8 baseline)

```
Baseline_total(A,B) = bas_4x8(A,B) × 256
Square_total(A,B)   = sqr_4x8_alpha_sqr(A) × 64
                    + sqr_4x8_sc(A,B) × 256
```

### config_2 — with both alpha arms (4×8 full)

```
Baseline_total(A,B) = bas_4x8(A,B) × 256
Square_total(A,B)   = sqr_4x8_alpha_sqr(A) × 64
                    + sqr_4x8_alpha_sum(A) × 48
                    + sqr_4x8_sc(A,B) × 256
```

### config_3 — reduced-array variant (8×8 PE array)

```
Baseline_total(A,B) = bas_4x8(A,B) × 64
Square_total(A,B)   = sqr_4x8_sc(A,B) × 64
                    + sqr_4x8_alpha_sqr(A) × 32
                    + sqr_4x8_alpha_sum(A) × 24
```

### config_4 — full-array split alpha lanes (8×16 PE array)

```
Baseline_total(A,B) = bas_4x8(A,B) × 128
Square_total(A,B)   = sqr_4x8_sc(A,B) × 128
                    + sqr_4x8_alpha_sqr(A) × 48
                    + sqr_4x8_alpha_sum(A) × 40
```

## Accumulator-input modelling

In `tb_top_sqr_4x8_sc.sv` (and the other 3-accumulator testbenches), the accumulator inputs are sized to reflect the alpha-block outputs they would carry in the system:

| Port     | Role                                          | Range                                                                    |
|----------|-----------------------------------------------|--------------------------------------------------------------------------|
| `acc[0]` | "carry-in" from outside                       | full `ACC_WIDTH` (48-bit) random                                         |
| `acc[1]` | output of α² (`sqr_4x8_sc_alpha` IS_SQUARE=1) | uniform in `[0, ALPHA_LANES × MAX_VAL_A²]`                               |
| `acc[2]` | output of α  (`sqr_4x8_sc_alpha` IS_SQUARE=0) | uniform signed in `[−ALPHA_LANES × MAX_VAL_A, +ALPHA_LANES × MAX_VAL_A]` |

`ALPHA_LANES` = `IN_SIZE` of the matching alpha block: **32** for the 4×8 family (`sqr_4x8_sc`, `win_4x8`, `win_4x8_sc`), **16** for the 8×8 family (`sqr_8x8`). The Winograd variants use 32 for consistency even though they do not have a literal alpha module.

## How to run

```bash
source sourceme.sh
python3 scripts/flow/dyn_range/run.py # 72 sweep points (idempotent)
python3 scripts/flow/dyn_range/ext.py # imp/ → doc/data/dyn_range/results.xlsx
python3 scripts/flow/dyn_range/gen.py # xlsx → 6 PNGs under doc/charts/dyn_range/
```
