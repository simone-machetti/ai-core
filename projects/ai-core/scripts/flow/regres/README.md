# Regression

End-to-end sanity-and-characterisation flow for the design library: run every synthesis / sim / post-syn stage for every architecture, extract per-design area / f_max / power, and plot the comparison charts.

The experiment has three stages:

1. `**run.py**` — runs `make sim`, `make syn`, `make post-syn-sim`, `make post-syn-sta`, `make post-syn-dpa` for every architecture; reports PASS / FAIL per (architecture, stage). Populates `sim/` and `imp/`.
2. `**ext.py**` — reads the report files left in `imp/` and writes `doc/data/regres/results.xlsx`.
3. `**gen.py**` — reads the xlsx and writes the eight comparison charts under `doc/charts/regres/`.

## Architectures


| Slug                | Top-level              | `MAX_VAL_A` | `MAX_VAL_B` | Extra params                 |
| ------------------- | ---------------------- | ----------- | ----------- | ---------------------------- |
| `bas_4x8`           | `top_bas_4x8`          | 7           | 127         | `IS_PIPELINED=1 MULT_TYPE=0` |
| `bas_8x8`           | `top_bas_8x8`          | 127         | 127         | `IS_PIPELINED=1 MULT_TYPE=0` |
| `bas_4x8_sc`        | `top_bas_4x8_sc`       | 7           | 127         | `IS_PIPELINED=1 MULT_TYPE=0` |
| `win_4x8`           | `top_win_4x8`          | 7           | 127         | `IS_PIPELINED=1 MULT_TYPE=0` |
| `win_4x8_sc`        | `top_win_4x8_sc`       | 7           | 127         | `IS_PIPELINED=1 MULT_TYPE=0` |
| `sqr_4x8_sc`        | `top_sqr_4x8_sc`       | 7           | 127         | `IS_PIPELINED=1`             |
| `sqr_8x8`           | `top_sqr_8x8`          | 127         | 127         | `IS_PIPELINED=1`             |
| `sqr_4x8_alpha`     | `top_sqr_4x8_sc_alpha` | 7           | —           | `IS_PIPELINED=1 IS_SQUARE=0` |
| `sqr_4x8_alpha_sqr` | `top_sqr_4x8_sc_alpha` | 7           | —           | `IS_PIPELINED=1 IS_SQUARE=1` |
| `sqr_8x8_alpha`     | `top_sqr_8x8_alpha`    | 127         | —           | `IS_PIPELINED=1 IS_SQUARE=0` |
| `sqr_8x8_alpha_sqr` | `top_sqr_8x8_alpha`    | 127         | —           | `IS_PIPELINED=1 IS_SQUARE=1` |


`DIST_TYPE=0` (uniform) is used for every regression point. The `_alpha` family takes no `B` input. `CLK_PERIOD_NS = 1.35` for every timed stage.

## Stages run per architecture

1. `make sim` — RTL simulation
2. `make syn` — Yosys synthesis
3. `make post-syn-sim` — gate-level simulation, produces `activity.vcd`
4. `make post-syn-sta` — OpenSTA timing analysis
5. `make post-syn-dpa` — OpenSTA power analysis

## Run outputs

- `sim/<slug>_sim/` and `sim/<slug>_post_syn_sim/`
- `imp/<slug>_syn/`, `imp/<slug>_post_syn_sta/`, `imp/<slug>_post_syn_dpa/`
- Per-call logs under `imp/_regres_logs/<slug>_<stage>.log`
- PASS / FAIL summary on stdout; `run.py` exits 0 iff all 55 calls pass.

## Extract inputs

For each architecture, three OpenROAD / OpenSTA report files are consumed:


| Metric                   | Source                                              | Parsing rule                                                                               |
| ------------------------ | --------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Area (µm²)               | `imp/<slug>_syn/report/area.rpt`                    | last whitespace-token on the `Chip area for module` line                                   |
| Slack (ps) → f_max (MHz) | `imp/<slug>_post_syn_sta/report/critical_paths.rpt` | first token on the `slack (MET|VIOLATED)` line; converted via `1000 / (1.35 − slack/1000)` |
| Power (W) → mW           | `imp/<slug>_post_syn_dpa/report/power_summary.rpt`  | 5th column of the `Total` row                                                              |


Architectures with no synthesis output yet are skipped (logged).

## Extract output

`doc/data/regres/results.xlsx` — one sheet `data`, four columns (`design`, `area_um2`, `freq_mhz`, `power_mw`), one row per design that has reports.

## Chart outputs

- `doc/charts/regres/area_pe_level.png` — per-design area bar chart
- `doc/charts/regres/area_ai_core_level_8.png` — 8×8 AI-core stacked comparison
- `doc/charts/regres/area_ai_core_level_16.png` — 16×16 AI-core stacked comparison
- `doc/charts/regres/freq_pe_level.png` — per-design f_max bar chart
- `doc/charts/regres/freq_ai_core_level.png` — AI-core f_max comparison (min over components)
- `doc/charts/regres/power_pe_level.png` — per-design power bar chart
- `doc/charts/regres/power_ai_core_level_8.png` — 8×8 AI-core stacked comparison
- `doc/charts/regres/power_ai_core_level_16.png` — 16×16 AI-core stacked comparison

### AI-core composition rules

For an `N×N` PE array (N ∈ {8, 16}):

- **Baseline 4×8** total = `N² × bas_4x8`
- **Baseline 8×8** total = `N² × bas_8x8`
- **Square 4×8** total = `N² × sqr_4x8_sc` + `N × 4 × sqr_4x8_alpha_sqr` *(+ `N × 3 × sqr_4x8_alpha` for power only)*
- **Square 8×8** total = `N² × sqr_8x8` + `N × 4 × sqr_8x8_alpha_sqr`

For frequency the AI-core f_max is the **minimum** across its component designs (no stacking, no summing).

## How to run

```bash
source sourceme.sh
python3 scripts/flow/regres/run.py # full flow per architecture, PASS/FAIL
python3 scripts/flow/regres/ext.py # imp/ → doc/data/regres/results.xlsx
python3 scripts/flow/regres/gen.py # → doc/charts/regres/*.png
```

