# AI-Core

Fixed-point multiply-accumulate Processing Elements (PEs) for AI/ML inference, implemented in SystemVerilog. It explores several algorithmic variants — Baseline, Winograd, and Squaring — each available in standard and split-cell configurations, and characterizes them through simulation, logic synthesis, static timing analysis, and dynamic power analysis.

This project plugs into the repository-level EDA flow. See the [root README](../../README.md) for the `make` targets, their generic parameters, and the typical pipeline. This document covers the parts specific to `ai-core`: the available top-levels, the RTL elaboration parameters, the testbenches, the automation experiments, the PE architectures, and the RTL module reference.

## Quick start

```bash
source ../../sourceme.sh   # or: source sourceme.sh from the repository root

# Pre-synthesis simulation
make sim TOP_LEVEL=top_bas_4x8 CLK_PERIOD_NS=1.0 OUT_DIR=bas_4x8

# Logic synthesis
make syn TOP_LEVEL=top_bas_4x8 OUT_DIR=bas_4x8

# Post-synthesis gate-level simulation
make post-syn-sim TOP_LEVEL=top_bas_4x8 CLK_PERIOD_NS=1.0 OUT_DIR=bas_4x8_post_syn_sim NETLIST_DIR=bas_4x8

# Post-synthesis static timing analysis
make post-syn-sta TOP_LEVEL=top_bas_4x8 CLK_PERIOD_NS=1.0 OUT_DIR=bas_4x8_sta NETLIST_DIR=bas_4x8

# Post-synthesis dynamic power analysis
make post-syn-dpa TOP_LEVEL=top_bas_4x8 CLK_PERIOD_NS=1.0 OUT_DIR=bas_4x8_dpa NETLIST_DIR=bas_4x8 VCD_DIR=bas_4x8_post_syn_sim
```

`ai-core` is the default project, so `PROJECT=ai-core` can be omitted from every command above.

## Top-level modules

Pass one of these as `TOP_LEVEL`. Each has a matching testbench `tb_<top_level>` under `tb/`.

| Top level              | Testbench                 | Verified formula                                 |
| ---------------------- | ------------------------- | ------------------------------------------------ |
| `top_bas_4x8`          | `tb_top_bas_4x8`          | `Σ(a[i]×b[i]) + acc[0]`                          |
| `top_bas_8x8`          | `tb_top_bas_8x8`          | `Σ(a[i]×b[i]) + acc[0]`                          |
| `top_bas_4x8_sc`       | `tb_top_bas_4x8_sc`       | `Σ(a[i]×b[i]) + acc[0]`                          |
| `top_win_4x8`          | `tb_top_win_4x8`          | `Σ[(a[i+1]+b[i])×(a[i]+b[i+1])] + Σacc`          |
| `top_win_4x8_sc`       | `tb_top_win_4x8_sc`       | Winograd with B sub-lane split + Σacc            |
| `top_sqr_4x8_sc`       | `tb_top_sqr_4x8_sc`       | `Σ[(a[k]+b_lo[k])² + 16×(a[k]+b_hi[k])²] + Σacc` |
| `top_sqr_8x8`          | `tb_top_sqr_8x8`          | `Σ((a[i]+b[i])²) + acc[0] + acc[1] + acc[2]`     |
| `top_sqr_4x8_sc_alpha` | `tb_top_sqr_4x8_sc_alpha` | `Σ(a[i]²)` or `Σ(a[i])` depending on `IS_SQUARE` |
| `top_sqr_8x8_alpha`    | `tb_top_sqr_8x8_alpha`    | `Σ(a[i]²)` or `Σ(a[i])` depending on `IS_SQUARE` |

## RTL elaboration parameters

Passed via `PARAMS="KEY=VAL ..."` to `make sim`, `make syn`, and `make post-syn-sim`.

| Key            | Applies to                                  | Values                      | Description                                                                                                                                                                                 |
| -------------- | ------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MULT_TYPE`    | BAS and WIN top-levels                      | `0` (R4), `1` (R8)          | Booth encoding radix                                                                                                                                                                        |
| `IS_PIPELINED` | all top-levels                              | `0`, `1`                    | 2-cycle (`0`) or 3-cycle (`1`) latency                                                                                                                                                      |
| `IS_SQUARE`    | `top_sqr_4x8_sc_alpha`, `top_sqr_8x8_alpha` | `0`, `1`                    | Squaring (`1`) or passthrough (`0`) inputs                                                                                                                                                  |
| `SQR_TYPE`     | `top_sqr_4x8_sc`                            | `0`, `1`                    | `0` = `sqr_s_5_bit_v0` (structural via HA chain), `1` = `sqr_s_5_bit_v1` (flat KMap-minimized)                                                                                              |
| `MAX_VAL_A`    | sim and post-syn-sim, all top-levels        | `0`..`2^(IN_WIDTH_A-1)-1`   | Max positive value for `a` test inputs; values drawn from `[-MAX_VAL_A, +MAX_VAL_A]` (default: `2^(IN_WIDTH_A-1)-1`; `0` collapses `a` to zero)                                             |
| `MAX_VAL_B`    | sim and post-syn-sim, non-alpha top-levels  | `0`..`2^(IN_WIDTH_B-1)-1`   | Max positive value for `b` test inputs; values drawn from `[-MAX_VAL_B, +MAX_VAL_B]` (default: `2^(IN_WIDTH_B-1)-1`)                                                                        |
| `DIST_TYPE`    | sim and post-syn-sim, all top-levels        | `0` (uniform), `1` (normal) | Random input distribution: uniform over `[-MAX_VAL_*, +MAX_VAL_*]` or bimodal normal at `±MU_SCALE × MAX_VAL_*` with std-dev `SIGMA_SCALE × MAX_VAL_*`, random sign per sample (Box-Muller) |
| `MU_SCALE`     | sim and post-syn-sim, all top-levels        | real                        | Mean of the normal distribution as a fraction of `MAX_VAL_*` (default: `1/2`; flow scripts override to `7/8`)                                                                               |
| `SIGMA_SCALE`  | sim and post-syn-sim, all top-levels        | real                        | Std-dev of the normal distribution as a fraction of `MAX_VAL_*` (default: `1/6`; flow scripts override to `1/8`)                                                                            |

## Testbenches

All testbenches share the same pattern — clock/reset generation with a configurable period, 1000 iterations of randomized inputs and accumulator values, corner cases (max-positive, min-negative, mixed-sign, zero), and self-checking via a software reference model that calls `$fatal` on any mismatch. Outputs go to `sim/<OUT_DIR>/`. An `activity.vcd` waveform is produced for debugging and power analysis purposes.

Random inputs are generated by `gen_a()` / `gen_b()` helper functions controlled by `MAX_VAL_A`, `MAX_VAL_B`, `DIST_TYPE`, `MU_SCALE`, and `SIGMA_SCALE`. `MAX_VAL_*` is the maximum positive value (in the signed-positive range) directly — e.g. for 4-bit signed inputs the valid range is `0..7`, and for 8-bit signed inputs it is `0..127` (setting `MAX_VAL_* = 0` collapses the input to zero). This permits arbitrary linear sweeps of the input dynamic range. When `DIST_TYPE=0` (uniform), values are drawn uniformly over the symmetric range `[-MAX_VAL_*, +MAX_VAL_*]`. When `DIST_TYPE=1` (normal), a Box-Muller transform produces a Gaussian with mean `MU_SCALE × MAX_VAL_*` and std-dev `SIGMA_SCALE × MAX_VAL_*`; samples are clamped to the absolute signed range of the full input width and then randomly negated, yielding a bimodal cluster at `±MU_SCALE × MAX_VAL_*`. With the defaults (`MU_SCALE=1/2`, `SIGMA_SCALE=1/6`) the `3σ` window of each lobe just spans `[0, MAX_VAL_*]`, giving a balanced bounded-Gaussian fill; the `dyn_range` / `a_sweep` flows override to `MU_SCALE=7/8`, `SIGMA_SCALE=1/8` for a tight near-max cluster. Corner cases (`verify_with_corner`) test `±MAX_VAL_*` directly.

## Experiments (automation scripts)

To characterize all PE variants at once, use the automation scripts under `scripts/flow/`. Each experiment is a subfolder containing three stage scripts plus a `README.md`:

- `run.py` — runs the relevant `make` targets and stores artifacts under `sim/` and `imp/`.
- `ext.py` — reads `sim/` and `imp/` and writes `doc/data/<exp>/results.xlsx`.
- `gen.py` — reads the xlsx and writes `doc/charts/<exp>/<chart>.png`.
- `README.md` — sweep parameters, architectures, formulas, and outputs.

Current experiments:

```bash
python3 scripts/flow/regres/run.py    # full flow per PE variant; PASS/FAIL
python3 scripts/flow/regres/ext.py    # imp/ → doc/data/regres/results.xlsx
python3 scripts/flow/regres/gen.py    # → doc/charts/regres/*.png

python3 scripts/flow/a_sweep/run.py   # A-magnitude sweep (reuses dyn syn dirs)
python3 scripts/flow/a_sweep/ext.py   # → doc/data/a_sweep/results.xlsx
python3 scripts/flow/a_sweep/gen.py   # → doc/charts/a_sweep/improvement.png

python3 scripts/flow/dyn_range/run.py # 2-D dynamic-range sweep, normal dist
python3 scripts/flow/dyn_range/ext.py # → doc/data/dyn_range/results.xlsx
python3 scripts/flow/dyn_range/gen.py # → doc/charts/dyn_range/*.png
```

Each experiment can also be driven through the root Makefile with `make flow-run EXP=<experiment>` (and likewise `flow-ext` / `flow-gen`), where `<experiment>` is `regres`, `a_sweep`, or `dyn_range`. Run `make flow-list PROJECT=ai-core` to list them.

## PE architectures

### Module instantiation map

| Top-level              | Partial product generator               | Compression tree     | Accumulators |
|------------------------|-----------------------------------------|----------------------|:------------:|
| `top_bas_4x8`          | `bas_4x8` → `mult_array`                | `cpr_tree_4x8`       | 1            |
| `top_bas_8x8`          | `bas_8x8` → `mult_array`                | `cpr_tree_8x8`       | 1            |
| `top_bas_4x8_sc`       | `bas_4x8_sc` → `mult_array`             | `cpr_tree_4x8`       | 1            |
| `top_win_4x8`          | `win_4x8` → `add_mult_array`            | `cpr_tree_4x8`       | 3            |
| `top_win_4x8_sc`       | `win_4x8_sc` → `add_mult_array`         | `cpr_tree_4x8`       | 3            |
| `top_sqr_4x8_sc`       | `sqr_4x8_sc` → `add_sqr_s_5_bit_array`  | `cpr_tree_4x8`       | 3            |
| `top_sqr_8x8`          | `add_sqr_s_9_bit_array`                 | `cpr_tree_8x8`       | 3            |
| `top_sqr_4x8_sc_alpha` | `sqr_s_4_bit_alpha_array`               | `cpr_tree_4x8_alpha` | 0            |
| `top_sqr_8x8_alpha`    | `sqr_s_8_bit_alpha_array`               | `cpr_tree_8x8_alpha` | 0            |

### Common pipeline

All PE variants share the same 3-stage pipeline:

```
Input FFs (ff_n) → Partial Product Generator → Compression Tree → Output FF
```

- **Stage 1**: `ff_n` registers the `a_i` and `b_i` input arrays.
- **Stage 2**: the partial product generator produces compressed partial sums; the compression tree begins reduction in stage 0 and optionally stores the result in a pipeline register (`IS_PIPELINED=1`).
- **Stage 3**: the compression tree completes the reduction; `ff` registers the final 48-bit output.

With `IS_PIPELINED=1` the latency is 3 clock cycles; with `IS_PIPELINED=0` it is 2 clock cycles.

### Baseline 4x8

**Formula:** `out = Σ(a[i] × b[i]) + acc[0]`

Directly multiplies 64 pairs of 4-bit A and 8-bit B operands using a Booth multiplier array and sums the products with one 48-bit accumulator.

**Booth encoding** — selected at elaboration time by `MULT_TYPE`:

| `MULT_TYPE` | Encoding | Partial products per multiplier | Operations               |
| ----------- | -------- | ------------------------------- | ------------------------ |
| `0`         | Radix-4  | `(IN_WIDTH_A + 1) / 2`          | `{0, ±B, ±2B}`           |
| `1`         | Radix-8  | `(IN_WIDTH_A + 2) / 3`          | `{0, ±B, ±2B, ±3B, ±4B}` |

Radix-8 produces fewer partial products (faster compression) at the cost of a wider encoding table (the `±3B` term).

**Compression tree** — `cpr_tree` with 1 accumulator reduces all partial products to a 48-bit output in three stages:

```
Stage 0: 8 groups × (PP_SIZE/8) inputs → 8 groups × 2 outputs  [pipeline FF here if IS_PIPELINED=1]
Stage 1: 4 groups × 4 inputs           → 4 groups × 2 outputs
Stage 2: 2 groups × 4 inputs           → 2 groups × 2 outputs
Final:   4 outputs + 1 accumulator     → cpr_n_2 → add_n → 48-bit result
```

Between stages, `ext_n` conditionally sign/zero-extends and optionally left-shifts the compressor outputs to grow the bit width.

### Baseline 8x8

**Formula:** `out = Σ(a[i] × b[i]) + acc[0]`

Directly multiplies 32 pairs of 8-bit A and 8-bit B operands using a Booth multiplier array and sums the products with one 48-bit accumulator. Compared to Baseline 4x8, the wider A operand increases the number of partial products per multiplier, making this a higher-latency, higher-area variant.

**Booth encoding** — same R4/R8 selection via `MULT_TYPE`, with the partial product count scaling with the wider A operand:

| `MULT_TYPE` | Encoding | Partial products per multiplier |
| ----------- | -------- | ------------------------------- |
| `0`         | Radix-4  | `(8 + 1) / 2 = 4`               |
| `1`         | Radix-8  | `(8 + 2) / 3 = 3`               |

**Compression tree** — `cpr_tree_8x8` with 1 accumulator reduces all partial products to a 48-bit output in two stages:

```
Stage 0: 4 groups × (PP_SIZE/4) inputs → 4 groups × 2 outputs  [pipeline FF here if IS_PIPELINED=1]
Stage 1: 2 groups × 4 inputs           → 2 groups × 2 outputs
Final:   4 outputs + 1 accumulator     → cpr_n_2 → add_n → 48-bit result
```

### Baseline 4x8 Split-Cell

**Formula:** `out = Σ(a[i] × b[i]) + acc[0]`

Split-cell variant of `top_bas_4x8`. Decomposes the 8-bit B operand as `B = B_lo + 16 × B_hi`, processing each 4-bit half with a separate narrower Booth array. This reduces the critical path compared to the full 8-bit Booth array.

**Booth encoding** — same R4/R8 selection via `MULT_TYPE` as `top_bas_4x8`, applied independently to the B_lo and B_hi halves.

**Compression tree** — `cpr_tree` with 1 accumulator, same stage structure as `top_bas_4x8`.

### Winograd 4x8

**Formula:** `out = Σ[(a[i+1]+b[i]) × (a[i]+b[i+1])] + Σacc`

Exploits the identity `(a+b)(c+d)` to pair adjacent inputs and compute a single multiply per pair, halving the multiplier count compared to BAS. Requires 3 accumulator inputs to `cpr_tree` to account for the reformulated sum.

**Booth encoding** — same R4/R8 selection via `MULT_TYPE` as BAS, but the Booth array operates on pre-summed inputs `(a[i+1]+b[i])` and `(a[i]+b[i+1])` rather than raw operands.

**Compression tree** — `cpr_tree` with 3 accumulators:

```
Final: 4 outputs + 3 accumulators → cpr_n_2 → add_n → 48-bit result
```

### Winograd 4x8 Split-Cell

**Formula:** `out = Σ[(a[i+1]+b[i]) × (a[i]+b[i+1])] + Σacc`

Split-cell variant of `top_win_4x8`. Applies the same B decomposition (`B = B_lo + 16 × B_hi`) on top of the Winograd pairing, combining both optimizations.

**Booth encoding** — same R4/R8 selection via `MULT_TYPE`, applied to each B half after Winograd pre-summation.

**Compression tree** — `cpr_tree` with 3 accumulators, same stage structure as `top_win_4x8`.

### Square 4x8 Split-Cell

**Formula:** `out = Σ[(a[k]+b_lo[k])² + 16×(a[k]+b_hi[k])²] + Σacc`

Replaces Booth multiplication with squaring via the identity `a×b = [(a+b)² − a² − b²] / 2`, decomposing B as `B_lo + 16×B_hi`. Uses dedicated `sqr_s_5_bit_v0`/`sqr_s_5_bit_v1` squaring cells (selected via `SQR_TYPE`) instead of a Booth multiplier array, which are more area-efficient for this computation. No `MULT_TYPE` parameter. Operates over 64 lanes.

**Compression tree** — `cpr_tree` with 3 accumulators, same stage structure as `top_win_4x8`.

### Square 8x8

**Formula:** `out = Σ((a[i]+b[i])²) + acc[0] + acc[1] + acc[2]`

Squaring-based 8-bit × 8-bit PE over 32 lanes. Each lane sign-extends both 8-bit operands to 9 bits, sums them, then squares the result using a dedicated `sqr_s_9_bit` cell. No `MULT_TYPE` parameter — there is no Booth encoder. Requires 3 accumulators, matching the three squaring terms of the underlying identity.

**Compression tree** — `cpr_tree_8x8` with 3 accumulators and `EXT_BITS=4`:

```
Stage 0: 4 groups × 8 inputs → 4 groups × 2 outputs  [pipeline FF here if IS_PIPELINED=1]
Stage 1: 2 groups × 4 inputs → 2 groups × 2 outputs
Final:   4 outputs + 3 accumulators → cpr_n_2 → add_n → 48-bit result
```

### Square 4x8 Split-Cell Alpha

A reduced squaring variant with 32 input lanes and a dedicated `cpr_tree_4x8_alpha` that carries no accumulator inputs. Uses `sqr_s_4_bit` cells (signed 4-bit squarer) instead of the 5-bit cells in `top_sqr_4x8_sc`.

The `IS_SQUARE` parameter selects the operation:

| `IS_SQUARE` | Operation       | Formula    |
| ----------- | --------------- | ---------- |
| `1`         | Squaring        | `Σ(a[i]²)` |
| `0`         | Passthrough sum | `Σ(a[i])`  |

### Square 8x8 Alpha

A reduced squaring variant with 16 input lanes and a dedicated `cpr_tree_8x8_alpha` that carries no accumulator inputs. Uses `sqr_s_8_bit` cells (signed 8-bit squarer) for the squaring mode.

The `IS_SQUARE` parameter selects the operation:

| `IS_SQUARE` | Operation       | Formula    |
| ----------- | --------------- | ---------- |
| `1`         | Squaring        | `Σ(a[i]²)` |
| `0`         | Passthrough sum | `Σ(a[i])`  |

**Compression tree** — `cpr_tree_8x8_alpha` with no accumulators and `CPR_EXT_BITS=4`:

```
Stage 0: 2 groups × 8 inputs → 2 groups × 2 outputs  [pipeline FF here if IS_PIPELINED=1]
Stage 1: 1 group  × 4 inputs → 1 group  × 2 outputs
Final:   2 outputs → add_n → (PP_WIDTH + CPR_EXT_BITS + 16)-bit result
```

## RTL modules reference

### Primitives

| Module      | Description                                                     |
| ----------- | --------------------------------------------------------------- |
| `fa`        | 1-bit full adder                                                |
| `ha`        | 1-bit half adder                                                |
| `ff`        | WIDTH-bit D flip-flop with active-low asynchronous reset        |
| `ff_n`      | Array of SIZE D flip-flops, WIDTH bits each                     |
| `sign_ext`  | Sign extension from IN_WIDTH to OUT_WIDTH bits                  |
| `shifter_n` | Static barrel shifter for an array of values                    |
| `ext_n`     | Runtime-controlled sign/zero extension with optional left shift |
| `add_n`     | Signed (IN_WIDTH+1)-bit adder                                   |
| `adder_n`   | Signed SIZE-bit adder                                           |

### Compressor hierarchy

| Module               | Description                                                           |
| -------------------- | --------------------------------------------------------------------- |
| `cpr_4_2_bit`        | 1-bit 4:2 compressor cell (two cascaded full adders)                  |
| `cpr_4_2`            | Multi-bit 4:2 compressor with sign extension                          |
| `cpr_n_2`            | Tree of 4:2 compressors reducing N inputs to sum + carry              |
| `cpr_tree_4x8`       | 3-stage compression tree for 4×8 PEs (PP_SIZE multiple of 8)          |
| `cpr_tree_8x8`       | 2-stage compression tree for 8×8 PEs (PP_SIZE multiple of 4)          |
| `cpr_tree_4x8_alpha` | 3-stage compression tree (no accumulators) for `top_sqr_4x8_sc_alpha` |
| `cpr_tree_8x8_alpha` | 2-stage compression tree (no accumulators) for `top_sqr_8x8_alpha`    |

### Booth multipliers

| Module          | Description                                               |
| --------------- | --------------------------------------------------------- |
| `booth_r4_cell` | Radix-4 Booth encoder cell: `{0, ±B, ±2B}`                |
| `booth_r4`      | Radix-4 Booth multiplier (`PP_SIZE = (A_width+1)/2`)      |
| `booth_r8_cell` | Radix-8 Booth encoder cell: `{0, ±B, ±2B, ±3B, ±4B}`      |
| `booth_r8`      | Radix-8 Booth multiplier (`PP_SIZE = (A_width+2)/3`)      |
| `mult_array`    | Array of parallel Booth multipliers (R4 or R8 selectable) |

### Squaring units

| Module                    | Description                                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------- |
| `sqr_u_3_bit`             | Unsigned 3-bit squarer (combinational truth-table logic)                                 |
| `sqr_u_4_bit`             | Unsigned 4-bit squarer (combinational truth-table logic)                                 |
| `sqr_u_8_bit`             | Unsigned 8-bit squarer (Wallace tree, no final carry-propagate adder)                    |
| `sqr_s_4_bit`             | Signed 4-bit squarer (2's complement → magnitude + sqr_u_3_bit)                          |
| `sqr_s_5_bit_v0`          | Signed 5-bit squarer, structural (2's complement → magnitude + sqr_u_4_bit via HA chain) |
| `sqr_s_5_bit_v1`          | Signed 5-bit squarer, optimized (flat KMap-minimized Boolean, no submodules)             |
| `sqr_s_8_bit`             | Signed 8-bit squarer (2's complement → magnitude + sqr_u_8_bit)                          |
| `sqr_s_9_bit`             | Signed 9-bit squarer (2's complement → magnitude + sqr_u_8_bit)                          |
| `sqr_s_4_bit_alpha_array` | Array: `a[i]²` or `a[i]` passthrough for 4-bit inputs, `IS_SQUARE`                       |
| `sqr_s_8_bit_alpha_array` | Array: `a[i]²` or `a[i]` passthrough for 8-bit inputs, `IS_SQUARE`                       |
| `add_sqr_s_5_bit_array`   | Array: `pp[i] = (a[i]+b[i])²`, `SQR_TYPE` selects v0/v1 (4-bit inputs)                   |
| `add_sqr_s_9_bit_array`   | Array: `pp[i] = (a[i]+b[i])²` using `sqr_s_9_bit` (8-bit inputs)                         |

### Partial product generators

| Module                  | Description                                                    |
| ----------------------- | -------------------------------------------------------------- |
| `bas_4x8`               | Baseline 4×8 PP generator (full 8-bit B)                       |
| `bas_8x8`               | Baseline 8×8 PP generator (32 lanes, 8-bit A and B)            |
| `bas_4x8_sc`            | Baseline split-cell (B split into B_lo and B_hi halves)        |
| `add_mult_array`        | Winograd pairing: `(a[i+1]+b[i]) × (a[i]+b[i+1])` per pair     |
| `win_4x8`               | Winograd 4×8 PP generator                                      |
| `win_4x8_sc`            | Winograd split-cell                                            |
| `sqr_4x8_sc`            | Squaring split-cell: `(a+b_lo)² + 16*(a+b_hi)²` per lane       |
| `add_sqr_s_9_bit_array` | Array: `pp[i] = (a[i]+b[i])²` for `top_sqr_8x8` (8-bit inputs) |
