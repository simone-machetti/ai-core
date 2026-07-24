# AI Core

Multi-project sandbox for prototyping RTL designs, built around the `ai-core` design project. The flow (Verilator simulation, Yosys synthesis, OpenROAD place-and-route, OpenSTA timing & dynamic power) is project-agnostic and lives at the repository root; each design sits under `projects/<name>/`, so additional projects can be added later without touching the shared flow.

Projects:

- [`ai-core`](projects/ai-core/README.md) — next-generation AI-Core architecture (clean redesign, in progress).

This README documents the shared EDA flow: the `make` targets, their parameters, and the typical pipeline. For a project's designs, top-levels, RTL parameters, and experiments, see that project's own README.

## Cloning

```bash
git clone https://github.com/simone-machetti/ai-core.git
cd ai-core
```

## Quick start

```bash
source sourceme.sh

# Pre-synthesis simulation
make sim PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name>

# Logic synthesis
make syn PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name>

# Post-synthesis gate-level simulation
make post-syn-sim PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-synthesis static timing analysis
make post-syn-sta PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-synthesis dynamic power analysis
make post-syn-dpa PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name> VCD_DIR=<name>

# Place-and-route
make pnr PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-place-and-route gate-level simulation
make post-pnr-sim PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-place-and-route static timing analysis
make post-pnr-sta PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-place-and-route dynamic power analysis
make post-pnr-dpa PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name> VCD_DIR=<name>
```

`PROJECT` and `TOP_LEVEL` are required on every command — there is no default. See `projects/<project>/README.md` for the available `TOP_LEVEL` values and runnable examples.

## Repository structure

```
.
├── .claude/
│   └── skills/           # Claude Code skills (add-project)
├── scripts/              # Project-agnostic EDA flow scripts
│   ├── sim/              # Pre-synthesis simulation flow
│   │   └── run.sh        # Verilator compile and run script
│   ├── syn/              # Logic synthesis flow
│   │   ├── run.tcl       # Yosys top-level synthesis script (ASAP7)
│   │   ├── compile.tcl   # RTL read and elaboration script
│   │   └── abc.tcl       # ABC technology mapping script
│   ├── pnr/              # Place-and-route flow (OpenROAD, ASAP7)
│   │   ├── run.sh        # Stage sequencer (one openroad process per stage)
│   │   ├── init_tech.tcl # Liberty reads and ASAP7 technology settings
│   │   ├── checkpoint.tcl# ODB checkpoint save/load helpers
│   │   ├── constraints.tcl # Clock constraints from CLK_PERIOD_NS
│   │   ├── reports.tcl   # Per-stage timing/area report helper
│   │   ├── 1_floorplan.tcl # Floorplan, tracks, pins, tie/tap cells, PDN
│   │   ├── 2_place.tcl   # Global and detailed placement
│   │   ├── 3_cts.tcl     # Clock tree synthesis
│   │   ├── 4_route.tcl   # Global and detailed routing
│   │   ├── 5_final.tcl   # Fillers, SPEF extraction, reports, final products
│   │   ├── 6_gds.sh      # DEF-to-GDS merge (KLayout)
│   │   └── def2stream.py # KLayout DEF/GDS streaming script (from ORFS)
│   ├── post-syn-sta/     # Post-synthesis static timing analysis flow
│   │   └── run.tcl       # OpenSTA timing analysis script
│   ├── post-syn-sim/     # Post-synthesis gate-level simulation flow
│   │   ├── run.sh        # Verilator compile and run script
│   │   └── filelist.f    # Gate-level netlist and cell library filelist
│   ├── post-syn-dpa/     # Post-synthesis dynamic power analysis flow
│   │   └── run.tcl       # OpenSTA power analysis script
│   ├── post-pnr-sta/     # Post-place-and-route static timing analysis flow
│   │   └── run.tcl       # OpenSTA timing analysis script (netlist + SPEF)
│   ├── post-pnr-sim/     # Post-place-and-route gate-level simulation flow
│   │   ├── run.sh        # Verilator compile and run script
│   │   └── filelist.f    # Routed netlist and cell library filelist
│   └── post-pnr-dpa/     # Post-place-and-route dynamic power analysis flow
│       └── run.tcl       # OpenSTA power analysis script (netlist + SPEF)
├── projects/             # One subfolder per RTL project
│   └── <name>/           # An RTL project (see its README.md)
│       ├── README.md     # Project-specific documentation
│       ├── rtl/          # SystemVerilog source modules
│       ├── tb/           # Verilator SV testbenches
│       ├── scripts/      # Project-specific scripts (sweeps, generators; run directly)
│       ├── doc/          # Documentation and results
│       │   ├── diagrams/ # Block diagrams
│       │   ├── formulas/ # Mathematical formulas
│       │   ├── charts/   # Charts and their generator scripts (generated)
│       │   └── data/     # Extracted results — .xlsx etc. (generated)
│       ├── wiki/         # OKF design-doc wiki (Obsidian vault)
│       ├── sim/          # Simulation outputs (generated)
│       └── imp/          # Synthesis/P&R/STA/DPA outputs (generated)
├── Makefile              # Build system entry point (PROJECT=<name> selects project)
├── sourceme.sh           # Environment setup (sources ~/.bashrc, derives REPO_HOME)
└── CLAUDE.md             # AI assistant guidance for this repository
```

All `make` targets require `PROJECT=<name>` to select the project they operate on (there is no default; targets fail fast if it is unset or names a project that does not exist). The flow scripts in `scripts/` resolve project-specific paths through the `SEL_PROJECT` env var exported by the Makefile.

## Environment setup

Tool and PDK install locations are **per-user**: you declare them in your `~/.bashrc`, and `sourceme.sh` sources that file and derives the rest. Run this once per shell before any `make` command:

```bash
source sourceme.sh
```

`sourceme.sh` sets `REPO_HOME` from its own location, sources `~/.bashrc`, then derives `ASAP7_HOME` from `PDK_HOME`. You therefore export only the install **roots** in your `~/.bashrc` — the shared flow itself is project- and machine-agnostic:

| Variable                                                           | Purpose                                                                                                                                                 |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EDA_HOME`                                                         | Root holding the EDA tool installs.                                                                                                                     |
| `VERILATOR_HOME`, `YOSYS_HOME`, `YOSYS_SLANG_HOME`, `OPENSTA_HOME`, `OPENROAD_HOME` | Per-tool install dirs (conventionally `$EDA_HOME/<tool>`); each tool's `bin/` must be on `PATH`.                                                        |
| `PDK_HOME`                                                         | Root holding the PDK trees — the ASAP7 standard-cell liberty (`.lib`), verilog (`.v`), LEF and GDS consumed by synthesis, place-and-route, STA, DPA and gate-level simulation. |

A minimal `~/.bashrc` block — add this and adjust the two roots (`EDA_HOME` and `PDK_HOME`) to your machine:

```bash
# --- EDA tool binaries ---
export EDA_HOME=/opt/eda
export VERILATOR_HOME=$EDA_HOME/verilator
export YOSYS_HOME=$EDA_HOME/yosys
export YOSYS_SLANG_HOME=$EDA_HOME/yosys-slang
export OPENSTA_HOME=$EDA_HOME/opensta
export OPENROAD_HOME=$EDA_HOME/openroad
export PATH=$VERILATOR_HOME/bin:$YOSYS_HOME/bin:$YOSYS_SLANG_HOME/bin:$OPENSTA_HOME/bin:$OPENROAD_HOME/bin:$PATH

# --- PDK ---
export PDK_HOME=/opt/pdks
```

Notes:

- **Do not** set `REPO_HOME` — `sourceme.sh` derives it from its own location, so the repo works unchanged if renamed or reused for a different project.
- `ASAP7_HOME` defaults to `$PDK_HOME/OpenROAD-flow-scripts/flow/platforms/asap7`; export it in `~/.bashrc` to target a different platform/technology.
- The final `make pnr` stage (DEF-to-GDS merge) additionally needs `klayout` on `PATH`. A system-wide install (e.g. the official `.deb` from [klayout.de](https://www.klayout.de/build.html), version ≥ 0.28) is fine — no `~/.bashrc` entry needed. The flow produces the routed DEF/ODB without it and errors clearly at the GDS stage if it is missing.

## Typical workflow

The make targets form a pipeline where earlier steps produce artifacts consumed by later ones:

1. `make sim` — functional verification (pass `VCD=1` to also dump `activity.vcd`).
2. `make syn` — logic synthesis; produces the netlist consumed by all post-synthesis flows.
3. `make post-syn-sim` — gate-level functional verification; produces `activity.vcd` consumed by `make post-syn-dpa`.
4. `make post-syn-sta` — static timing analysis from the synthesized netlist.
5. `make post-syn-dpa` — power estimation using the synthesized netlist and the `activity.vcd` from `make post-syn-sim`.
6. `make pnr` — place-and-route of the synthesized netlist; produces the final layout (DEF/ODB/GDS), the routed netlist and its extracted parasitics (SPEF), consumed by all post-place-and-route flows.
7. `make post-pnr-sim` — gate-level functional verification of the routed netlist; produces `activity.vcd` consumed by `make post-pnr-dpa`.
8. `make post-pnr-sta` — parasitics-accurate static timing analysis from the routed netlist and SPEF.
9. `make post-pnr-dpa` — parasitics-accurate power estimation using the routed netlist, SPEF and the `activity.vcd` from `make post-pnr-sim`.

## Skills

This repository ships [Claude Code](https://claude.com/claude-code) skills under [.claude/skills/](.claude/skills/). They automate the repetitive parts of working in this sandbox — scaffolding a new project, and maintaining a project's OKF design-doc wiki. Invoke a skill by name (e.g. `/add-project my-accel`) in a Claude Code session.

| Skill                                                | Purpose                                                                                                                                                                                                                              |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`add-project`](.claude/skills/add-project/SKILL.md) | Scaffold a new empty project under `projects/<name>/`: creates the `rtl/`, `tb/`, `scripts/`, and `doc/` skeleton, runs `make init`, writes a stub project README, and registers the project in this README's `Projects:` list.      |
| [`update-wiki`](.claude/skills/update-wiki/SKILL.md) | Update a project's OKF design-doc wiki under `projects/<project>/wiki/` after design progress: ingest new/changed `rtl/`, `tb/`, `doc/` into concept pages, refresh `index.md`/`log.md`, and lint for OKF conformance.               |

A typical greenfield flow is `/add-project` to create the skeleton, then populate `rtl/` and `tb/` to verify, characterize, and document the design.

## Commands

The `TOP_LEVEL` values and `PARAMS` keys are project-specific; the syntax below is the shared interface. See the project README for the available top-levels and elaboration parameters.

### Pre-synthesis simulation (Verilator)

```bash
make sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1]
```

| Parameter       | Required | Description                                                                                                    |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------------- |
| `TOP_LEVEL`     | yes      | RTL module to simulate                                                                                         |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                                                                    |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`                                                                               |
| `TB`            | no       | Testbench module to run; default `tb_<top_level>`                                                              |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters                                                                    |
| `VCD`           | no       | `1` enables Verilator tracing and dumps `activity.vcd`; default `0` (off — tracing is costly on large designs) |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`. Pass `VCD=1` to also dump an `activity.vcd` waveform (off by default).

### Logic synthesis (Yosys + ABC, ASAP7 target)

```bash
make syn TOP_LEVEL=<top_level> OUT_DIR=<name> [CLK_PERIOD_NS=<val>] [PARAMS="KEY=VAL ..."] \
    [KEEP_HIERARCHY=1] [KEEP_MODULES="mod ..."] [BLACKBOX_MODULES="mod ..."]
```

| Parameter          | Required          | Description                                                                  |
| ------------------ | ----------------- | ---------------------------------------------------------------------------- |
| `TOP_LEVEL`        | yes               | RTL module to synthesize; can be any module in the hierarchy                 |
| `OUT_DIR`          | yes               | Output subdirectory under `imp/`                                             |
| `CLK_PERIOD_NS`    | no (default: 1.0) | Delay target for the ABC mapper (the resolved script is saved as `output/abc.script`) |
| `PARAMS`           | no                | Project-specific RTL elaboration parameters                                  |
| `KEEP_HIERARCHY`   | no (default: 0) | Preserve every module boundary in the netlist (skips `flatten`)              |
| `KEEP_MODULES`     | no              | Preserve only the listed module boundaries and flatten below them            |
| `BLACKBOX_MODULES` | no              | Do not elaborate the listed modules; link their netlists from an earlier run |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`.

#### Netlist hierarchy

| Mode               | Netlist                               | `report/area.rpt`                 |
| ------------------ | ------------------------------------- | --------------------------------- |
| default            | fully flat                            | one number                        |
| `KEEP_HIERARCHY=1` | every module boundary                 | every module                      |
| `KEEP_MODULES`     | listed modules only, flat inside each | top + listed modules              |
| `BLACKBOX_MODULES` | one shared module per listed name     | top + one entry per linked module |

The netlist of the BLACKBOX_MODULES is read from `imp/<mod>/output/netlist.v` and the run fails if it is missing. A linked module is not resynthesized, so its area is exactly the one from its own run — rerun the first pass after changing its RTL.

### Post-synthesis static timing analysis (OpenSTA)

```bash
make post-syn-sta TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir>
```

| Parameter       | Required | Description                                                  |
| --------------- | -------- | ------------------------------------------------------------ |
| `TOP_LEVEL`     | yes      | RTL module name                                              |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                  |
| `OUT_DIR`       | yes      | Output subdirectory under `imp/`                             |
| `NETLIST_DIR`   | yes      | Directory containing the synthesized netlist from `make syn` |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`.

### Post-synthesis gate-level simulation

```bash
make post-syn-sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> \
    [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1]
```

| Parameter       | Required | Description                                                                                          |
| --------------- | -------- | ---------------------------------------------------------------------------------------------------- |
| `TOP_LEVEL`     | yes      | RTL module to simulate                                                                               |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                                                          |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`                                                                     |
| `NETLIST_DIR`   | yes      | Directory containing the synthesized netlist from `make syn`                                         |
| `TB`            | no       | Testbench module to run; default `tb_<top_level>`                                                    |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters                                                          |
| `VCD`           | no       | `1` enables Verilator tracing and dumps `activity.vcd`; default `0`. Required by `make post-syn-dpa` |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`. Compiles the testbench with the `POST_SYN_SIM` compile-time flag, which the bench uses to instantiate the synthesized netlist instead of the RTL. Synthesis flattens unpacked array ports into single vectors and drops parameters, so a bench that drives such a top-level needs a `POST_SYN_SIM` branch that instantiates the DUT without parameters and wires the flat ports.

The ASAP7 sequential cells are read from `scripts/post-syn-sim/asap7_seq_behav.v` rather than from the PDK, because Verilator does not implement the 1995 UDP tables the PDK models are built on and miscompiles them silently — see [bugs.md](bugs.md). Add a model there if `dfflibmap` ever emits a cell it does not cover.

### Post-synthesis dynamic power analysis (OpenSTA)

```bash
make post-syn-dpa TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> VCD_DIR=<vcd_dir> \
    [TB=<testbench>] [KEEP_HIERARCHY=1] [KEEP_MODULES="mod ..."] [BLACKBOX_MODULES="mod ..."]
```

| Parameter          | Required        | Description                                                                       |
| ------------------ | --------------- | --------------------------------------------------------------------------------- |
| `TOP_LEVEL`        | yes             | RTL module name                                                                   |
| `CLK_PERIOD_NS`    | yes             | Clock period in nanoseconds                                                       |
| `OUT_DIR`          | yes             | Output subdirectory under `imp/`                                                  |
| `NETLIST_DIR`      | yes             | Directory containing the synthesized netlist from `make syn`                      |
| `VCD_DIR`          | yes             | Directory containing `activity.vcd` from `make post-syn-sim VCD=1`                |
| `TB`               | no              | Testbench module the VCD was dumped from; default `tb_<top_level>`                |
| `KEEP_HIERARCHY`   | no (default: 0) | Also generate `power_hierarchy.rpt` with a per-instance breakdown                 |
| `KEEP_MODULES`     | no              | Same effect as `KEEP_HIERARCHY=1` on the report; pass the value used at synthesis |
| `BLACKBOX_MODULES` | no              | Same effect as `KEEP_HIERARCHY=1` on the report; pass the value used at synthesis |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`. The VCD is annotated onto the scope `<TB>/dut`, so the testbench must name its DUT instance `dut`. `report/vcd_annotated.rpt` and `report/vcd_unannotated.rpt` list how many pins were annotated — a low count means the scope did not match and the power numbers are estimates, not measurements.

The per-instance report needs a netlist with module boundaries, so pass the same hierarchy parameters that were used for `make syn`.

### Place-and-route (OpenROAD, ASAP7 target)

```bash
make pnr TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> \
    [CORE_UTIL=<pct>] [ASPECT_RATIO=<val>] [CORE_MARGIN=<um>] [PLACE_DENSITY=<val>] \
    [CLK_UNCERTAINTY_PS=<val>] [PNR_STEP=<stage>]
```

| Parameter            | Required           | Description                                                                          |
| -------------------- | ------------------ | ------------------------------------------------------------------------------------ |
| `TOP_LEVEL`          | yes                | Module to place-and-route (must match the netlist top)                               |
| `CLK_PERIOD_NS`      | yes                | Clock period in nanoseconds                                                          |
| `OUT_DIR`            | yes                | Output subdirectory under `imp/`                                                     |
| `NETLIST_DIR`        | yes                | Directory containing the synthesized netlist from `make syn` (must be **flat**)      |
| `CORE_UTIL`          | no (default: 40)   | Core utilization percentage for the floorplan (die area derives from it)             |
| `ASPECT_RATIO`       | no (default: 1.0)  | Core height/width ratio                                                              |
| `CORE_MARGIN`        | no (default: 2)    | Margin between core and die edge, in µm                                              |
| `PLACE_DENSITY`      | no (default: 0.60) | Global placement target density                                                      |
| `CLK_UNCERTAINTY_PS` | no (default: 0)    | Clock uncertainty in picoseconds (0 = none)                                          |
| `PNR_STEP`           | no (default: all)  | `all` runs the full flow from a clean `OUT_DIR`; a single stage name re-runs just it |

The flow is six stages, each an independent `openroad` process chained through ODB checkpoints in `output/`: `1_floorplan` (floorplan, tracks, pin placement, tie/tap cells, power grid), `2_place` (global + detailed placement, buffering/sizing repair), `3_cts` (clock tree synthesis + setup repair), `4_route` (global + detailed routing, setup/hold repair), `5_final` (filler cells, SPEF extraction, final reports and products), `6_gds` (DEF-to-GDS merge via KLayout). With `PNR_STEP=<stage>` a single stage re-runs from the previous stage's checkpoint in the same `OUT_DIR` (no clean), e.g. `PNR_STEP=3_cts` after tweaking the CTS script.

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`:

- `output/design.def`, `output/design.odb`, `output/design.gds` — the final layout (open the ODB with `openroad -gui`, the GDS with `klayout`).
- `output/netlist.v` — the routed netlist (physical-only cells stripped), consumable by every `post-pnr-*` flow via `NETLIST_DIR`.
- `output/netlist.spef` — extracted post-route parasitics (OpenRCX).
- `output/design.sdc`, `output/abstract.lef`, `output/timing_model.lib` — constraints as implemented, plus the abstract LEF and liberty timing model that let a later hierarchical run consume this layout as a hard macro.
- `output/<stage>.odb`, `output/openroad_<stage>.log` — per-stage checkpoints and logs.
- `report/<stage>.rpt` — per-stage critical path, WNS, TNS and area; `report/route_drc.rpt` — detailed-route DRC violations (must be empty); `report/critical_paths.rpt`, `wns.rpt`, `tns.rpt`, `clock_skew.rpt`, `power.rpt`, `design_area.rpt` — final post-route reports.

The P&R input must be a **flat** netlist (default `make syn`, no `KEEP_*`/`BLACKBOX_*` options). Clock gates are fully supported: the `ICGx1_ASAP7_75t_R` cells synthesized into the design are placed and routed, and CTS balances the clock tree through them; the P&R optimizers are only forbidden from inserting new ICG cells on their own.

### Post-place-and-route static timing analysis (OpenSTA)

```bash
make post-pnr-sta TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir>
```

Same interface and reports as `make post-syn-sta`, but `NETLIST_DIR` points at a `make pnr` run: the routed `netlist.v` is linked and `netlist.spef` is read, so timing is parasitics-accurate with propagated clocks.

### Post-place-and-route gate-level simulation

```bash
make post-pnr-sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> \
    [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1]
```

Same interface and testbench conventions as `make post-syn-sim` (including the `POST_SYN_SIM` compile-time flag), but simulates the routed netlist from a `make pnr` run. Pass `VCD=1` to dump the `activity.vcd` consumed by `make post-pnr-dpa`.

### Post-place-and-route dynamic power analysis (OpenSTA)

```bash
make post-pnr-dpa TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> VCD_DIR=<vcd_dir> [TB=<testbench>]
```

Same interface as `make post-syn-dpa`, but `NETLIST_DIR` points at a `make pnr` run: the routed netlist and `netlist.spef` are read, so power is parasitics-accurate. `VCD_DIR` holds the `activity.vcd` from `make post-pnr-sim VCD=1`. The routed netlist is flat, so there is no per-instance hierarchy report.

### Experiment automation

Project-specific automation — synthesis sweeps, result extraction, and chart/table generation — lives under `projects/<PROJECT>/scripts/` and writes its outputs into that project's `doc/data/` (extracted results) and `doc/charts/` (generated charts). These are plain, self-contained scripts, **run directly** rather than through `make`:

```bash
bash   projects/<PROJECT>/scripts/<sweep>.sh    # drive a batch of make syn/sim runs
python projects/<PROJECT>/doc/charts/<chart>.py # (re)generate a chart from the extracted data
```

Each script embeds or reads the data it needs; see the project's own README for the experiments it provides.

### Cleanup

```bash
make clean-sim OUT_DIR=<name> # remove one simulation run
make clean-imp OUT_DIR=<name> # remove one synthesis/P&R/STA/DPA run
make clean-all                # remove all sim/ and imp/ directories
```

### Make-level parameters reference

| Parameter            | Make targets                                           | Values                          | Description                                                                                |
| -------------------- | ------------------------------------------------------ | ------------------------------- | ------------------------------------------------------------------------------------------ |
| `PROJECT`            | all                                                    | project name                    | Required. Project under `projects/` to operate on (no default)                             |
| `TOP_LEVEL`          | all except init and clean-*                            | module name                     | RTL module to build/simulate; can be any module in the hierarchy                           |
| `TB`                 | sim, post-syn-sim, post-syn-dpa, post-pnr-sim, post-pnr-dpa | testbench module name      | Testbench to run (default `tb_$(TOP_LEVEL)`); set it to use an alternative bench           |
| `CLK_PERIOD_NS`      | all except init and clean-*                            | e.g. `1.0`                      | Clock period in nanoseconds (for `syn`: the ABC delay target, default `1.0`)               |
| `OUT_DIR`            | all except clean-all                                   | directory name                  | Output subdirectory under `sim/` or `imp/`                                                 |
| `NETLIST_DIR`        | pnr, post-syn-*, post-pnr-*                            | e.g. `top_2x2`                  | Directory containing the netlist to consume (`make syn` for pnr/post-syn-*, `make pnr` for post-pnr-*) |
| `VCD_DIR`            | post-syn-dpa, post-pnr-dpa                             | e.g. `pwr_2x2`                  | Directory containing `activity.vcd` from the matching gate-level simulation                |
| `PARAMS`             | sim, syn, post-syn-sim, post-pnr-sim                   | `"KEY=VAL ..."`                 | Project-specific RTL elaboration parameters                                                |
| `VCD`                | sim, post-syn-sim, post-pnr-sim                        | `0` (default), `1`              | Enable Verilator tracing and dump `activity.vcd` (off by default; costly on large designs) |
| `KEEP_HIERARCHY`     | syn, post-syn-dpa                                      | `0` (default), `1`              | Preserve module boundaries in the netlist                                                  |
| `KEEP_MODULES`       | syn, post-syn-dpa                                      | `"mod ..."` (default: `none`)   | Preserve only the listed module boundaries and flatten everything below them               |
| `BLACKBOX_MODULES`   | syn, post-syn-dpa                                      | `"mod ..."` (default: `none`)   | Do not elaborate the listed modules; link their netlists from `imp/<mod>/output/netlist.v` |
| `CORE_UTIL`          | pnr                                                    | percent (default: `40`)         | Core utilization for the floorplan; die area derives from it                               |
| `ASPECT_RATIO`       | pnr                                                    | ratio (default: `1.0`)          | Core height/width ratio                                                                    |
| `CORE_MARGIN`        | pnr                                                    | µm (default: `2`)               | Margin between core area and die edge                                                      |
| `PLACE_DENSITY`      | pnr                                                    | 0–1 (default: `0.60`)           | Global placement target density                                                            |
| `CLK_UNCERTAINTY_PS` | pnr                                                    | ps (default: `0`)               | Clock uncertainty applied to the clock (0 = none)                                          |
| `PNR_STEP`           | pnr                                                    | `all` (default) or a stage name | `all` = full clean run; a stage name re-runs that stage from the previous checkpoint       |
