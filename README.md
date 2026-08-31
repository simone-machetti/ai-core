# AI Core

Multi-project sandbox for prototyping RTL designs, built around the `ai-core` design project. The flow (Verilator simulation, Yosys synthesis, OpenROAD place-and-route, OpenSTA timing & dynamic power) is project-agnostic and lives at the repository root; each design sits under `projects/<name>/`, so additional projects can be added later without touching the shared flow.

Projects:

- `ai-core` — next-generation AI-Core architecture (clean redesign, in progress).

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
│   └── skills/             # Claude Code skills (add-project)
├── scripts/                # Project-agnostic EDA flow scripts
│   ├── sim/                # Pre-synthesis simulation flow
│   │   └── run.sh          # Verilator compile and run script
│   ├── syn/                # Logic synthesis flow
│   │   ├── run.tcl         # Yosys top-level synthesis script (ASAP7)
│   │   ├── compile.tcl     # RTL read and elaboration script
│   │   └── abc.tcl         # ABC technology mapping script
│   ├── pnr/                # Place-and-route flow (OpenROAD, ASAP7)
│   │   ├── run.sh          # Stage sequencer (one openroad process per stage)
│   │   ├── init_tech.tcl   # Liberty reads and ASAP7 technology settings
│   │   ├── checkpoint.tcl  # ODB checkpoint save/load helpers
│   │   ├── constraints.tcl # Clock constraints from CLK_PERIOD_NS
│   │   ├── reports.tcl     # Per-stage timing/area report helper
│   │   ├── 1_floorplan.tcl # Floorplan, tracks, pins, tie/tap cells, PDN
│   │   ├── 2_place.tcl     # Global and detailed placement
│   │   ├── 3_cts.tcl       # Clock tree synthesis
│   │   ├── 4_route.tcl     # Global and detailed routing
│   │   ├── 5_final.tcl     # Fillers, SPEF extraction, reports, final products
│   │   ├── 6_gds.sh        # DEF-to-GDS merge (KLayout)
│   │   ├── pdn_macro.tcl   # Macro-aware PDN strategy (hierarchical runs)
│   │   └── def2stream.py   # KLayout DEF/GDS streaming script (from ORFS)
│   ├── post-syn-sta/       # Post-synthesis static timing analysis flow
│   │   └── run.tcl         # OpenSTA timing analysis script
│   ├── post-syn-sim/       # Post-synthesis gate-level simulation flow
│   │   ├── run.sh          # Verilator compile and run script
│   │   └── filelist.f      # Gate-level netlist and cell library filelist
│   ├── post-syn-dpa/       # Post-synthesis dynamic power analysis flow
│   │   └── run.tcl         # OpenSTA power analysis script
│   ├── post-pnr-sta/       # Post-place-and-route static timing analysis flow
│   │   └── run.tcl         # OpenSTA timing analysis script (netlist + SPEF)
│   ├── post-pnr-sim/       # Post-place-and-route gate-level simulation flow
│   │   ├── run.sh          # Verilator compile and run script
│   │   └── filelist.f      # Routed netlist and cell library filelist
│   └── post-pnr-dpa/       # Post-place-and-route dynamic power analysis flow
│       └── run.tcl         # OpenSTA power analysis script (netlist + SPEF)
├── projects/               # One subfolder per RTL project
│   └── <name>/             # An RTL project (see its README.md)
│       ├── README.md       # Project-specific documentation
│       ├── rtl/            # SystemVerilog source modules
│       ├── tb/             # Verilator SV testbenches
│       ├── scripts/        # Project-specific scripts (sweeps, generators; run directly)
│       ├── doc/            # Documentation and results
│       │   ├── diagrams/   # Block diagrams
│       │   ├── formulas/   # Mathematical formulas
│       │   ├── charts/     # Charts and their generator scripts (generated)
│       │   └── data/       # Extracted results — .xlsx etc. (generated)
│       ├── wiki/           # OKF design-doc wiki (Obsidian vault)
│       ├── sim/            # Simulation outputs (generated)
│       └── imp/            # Synthesis/P&R/STA/DPA outputs (generated)
├── Makefile                # Build system entry point (PROJECT=<name> selects project)
├── sourceme.sh             # Environment setup (sources ~/.bashrc, derives REPO_HOME)
└── CLAUDE.md               # AI assistant guidance for this repository
```

All `make` targets require `PROJECT=<name>` to select the project they operate on (there is no default; targets fail fast if it is unset or names a project that does not exist). The flow scripts in `scripts/` resolve project-specific paths through the `SEL_PROJECT` env var exported by the Makefile.

## Environment setup

Tool and PDK install locations are **per-user**: you declare them in your `~/.bashrc`, and `sourceme.sh` sources that file and derives the rest. Run this once per shell before any `make` command:

```bash
source sourceme.sh
```

`sourceme.sh` sets `REPO_HOME` from its own location, sources `~/.bashrc`, then derives `ASAP7_HOME` from `PDK_HOME`. You therefore export only the install **roots** in your `~/.bashrc` — the shared flow itself is project- and machine-agnostic:

| Variable                                                                            | Purpose                                                                                          |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `EDA_HOME`                                                                          | Root holding the EDA tool installs.                                                              |
| `VERILATOR_HOME`, `YOSYS_HOME`, `YOSYS_SLANG_HOME`, `OPENSTA_HOME`, `OPENROAD_HOME` | Per-tool install dirs (conventionally `$EDA_HOME/<tool>`); each tool's `bin/` must be on `PATH`. |
| `PDK_HOME`                                                                          | Root holding the PDK trees — the ASAP7 liberty, verilog, LEF and GDS consumed by the flow.       |

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
- The final `make pnr` stage (DEF-to-GDS merge) additionally needs `klayout` (≥ 0.28) on `PATH`; a system-wide install is fine. The flow produces the routed DEF/ODB without it and errors clearly at the GDS stage if it is missing.

## Typical workflow

The make targets form a pipeline where earlier steps produce artifacts consumed by later ones:

1. `make sim` — functional verification (pass `VCD=1` to also dump `activity.vcd`).
2. `make syn` — logic synthesis; produces the netlist consumed by all post-synthesis flows.
3. `make post-syn-sim` — gate-level functional verification; produces `activity.vcd` consumed by `make post-syn-dpa`.
4. `make post-syn-sta` — static timing analysis from the synthesized netlist.
5. `make post-syn-dpa` — power estimation using the synthesized netlist and the `activity.vcd` from `make post-syn-sim`.
6. `make pnr` — place-and-route of the synthesized netlist; produces the final layout, the routed netlist and its parasitics.
7. `make post-pnr-sim` — gate-level functional verification of the routed netlist; produces `activity.vcd` for `make post-pnr-dpa`.
8. `make post-pnr-sta` — parasitics-accurate static timing analysis from the routed netlist and SPEF.
9. `make post-pnr-dpa` — parasitics-accurate power estimation using the routed netlist, SPEF and the post-pnr `activity.vcd`.

## Skills

This repository ships [Claude Code](https://claude.com/claude-code) skills under [.claude/skills/](.claude/skills/). They automate the repetitive parts of working in this sandbox — scaffolding a new project, and maintaining a project's OKF design-doc wiki. Invoke a skill by name (e.g. `/add-project my-accel`) in a Claude Code session.

| Skill                                                | Purpose                                                                                                                                                                                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`add-project`](.claude/skills/add-project/SKILL.md) | Scaffold a new empty project under `projects/<name>/`: creates the `rtl/`, `tb/`, `scripts/`, and `doc/` skeleton, runs `make init`, writes a stub project README, and registers the project in this README's `Projects:` list. |
| [`update-wiki`](.claude/skills/update-wiki/SKILL.md) | Update a project's OKF design-doc wiki under `projects/<project>/wiki/` after design progress: ingest new/changed `rtl/`, `tb/`, `doc/` into concept pages, refresh `index.md`/`log.md`, and lint for OKF conformance.          |

A typical greenfield flow is `/add-project` to create the skeleton, then populate `rtl/` and `tb/` to verify, characterize, and document the design.

## Commands

The `TOP_LEVEL` values and `PARAMS` keys are project-specific; the syntax below is the shared interface. See the project README for the available top-levels and elaboration parameters.

### Pre-synthesis simulation (Verilator)

```bash
make sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1]
```

| Parameter       | Required | Description                                                     |
| --------------- | -------- | --------------------------------------------------------------- |
| `TOP_LEVEL`     | yes      | RTL module to simulate                                          |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                     |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`                                |
| `TB`            | no       | Testbench module to run; default `tb_<top_level>`               |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters                     |
| `VCD`           | no       | `1` enables tracing and dumps `activity.vcd`; default `0` (off) |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`.

### Logic synthesis (Yosys + ABC, ASAP7 target)

```bash
make syn TOP_LEVEL=<top_level> OUT_DIR=<name> [CLK_PERIOD_NS=<val>] [PARAMS="KEY=VAL ..."] \
    [KEEP_HIERARCHY=1] [KEEP_MODULES="mod ..."] [BLACKBOX_MODULES="mod ..."] [LINK_BLACKBOXES=0]
```

| Parameter          | Required          | Description                                                                    |
| ------------------ | ----------------- | ------------------------------------------------------------------------------ |
| `TOP_LEVEL`        | yes               | RTL module to synthesize; can be any module in the hierarchy                   |
| `OUT_DIR`          | yes               | Output subdirectory under `imp/`                                               |
| `CLK_PERIOD_NS`    | no (default: 1.0) | Delay target for the ABC mapper (resolved script saved as `output/abc.script`) |
| `PARAMS`           | no                | Project-specific RTL elaboration parameters                                    |
| `KEEP_HIERARCHY`   | no (default: 0)   | Preserve every module boundary in the netlist (skips `flatten`)                |
| `KEEP_MODULES`     | no                | Preserve only the listed module boundaries and flatten below them              |
| `BLACKBOX_MODULES` | no                | Do not elaborate the listed modules; link their netlists from an earlier run   |
| `LINK_BLACKBOXES`  | no (default: 1)   | `0` keeps the blackboxed modules as empty stubs for hierarchical `make pnr`    |

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

| Parameter       | Required | Description                                                       |
| --------------- | -------- | ----------------------------------------------------------------- |
| `TOP_LEVEL`     | yes      | RTL module to simulate                                            |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                       |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`                                  |
| `NETLIST_DIR`   | yes      | Directory containing the synthesized netlist from `make syn`      |
| `TB`            | no       | Testbench module to run; default `tb_<top_level>`                 |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters                       |
| `VCD`           | no       | `1` dumps `activity.vcd`; default `0`. Required by `post-syn-dpa` |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`. Compiles the testbench with the `POST_SYN_SIM` compile-time flag, which the bench uses to instantiate the synthesized netlist instead of the RTL. Synthesis flattens unpacked array ports into single vectors and drops parameters, so a bench that drives such a top-level needs a `POST_SYN_SIM` branch that instantiates the DUT without parameters and wires the flat ports.

The ASAP7 sequential cells are read from `scripts/post-syn-sim/asap7_seq_behav.v` rather than from the PDK, because Verilator does not implement the 1995 UDP tables the PDK models are built on and miscompiles them silently. Add a model there if `dfflibmap` ever emits a cell it does not cover.

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
    [MAX_ROUTE_LAYER=<layer>] [CLK_UNCERTAINTY_PS=<val>] [PNR_STEP=<stage>] [PNR_THREADS=<n>] \
    [MACRO_DIRS="dir ..."] [FLOORPLAN=<file>] [MACRO_CHANNEL=<um>] [PDN=<file>]
```

| Parameter            | Required           | Description                                                                                                |
| -------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------- |
| `TOP_LEVEL`          | yes                | Module to place-and-route (must match the netlist top)                                                     |
| `CLK_PERIOD_NS`      | yes                | Clock period in nanoseconds                                                                                |
| `OUT_DIR`            | yes                | Output subdirectory under `imp/`                                                                           |
| `NETLIST_DIR`        | yes                | Directory containing the flat netlist from `make syn`                                                      |
| `CORE_UTIL`          | no (default: 40)   | Core utilization percentage; the die area derives from it                                                  |
| `ASPECT_RATIO`       | no (default: 1.0)  | Core height/width ratio                                                                                    |
| `CORE_MARGIN`        | no (default: 2)    | Core-to-die margin in µm                                                                                   |
| `PLACE_DENSITY`      | no (default: 0.60) | Global placement target density                                                                            |
| `MAX_ROUTE_LAYER`    | no (default: M7)   | Top signal-routing layer; use `M6` when hardening a tile so M7 stays free for the parent PDN               |
| `CLK_UNCERTAINTY_PS` | no (default: 0)    | Clock uncertainty in picoseconds                                                                           |
| `PNR_STEP`           | no (default: all)  | `all` = full clean run; a stage name re-runs only that stage                                               |
| `PNR_THREADS`        | no (default: 0)    | OpenROAD thread count; `0` = all cores                                                                     |
| `MACRO_DIRS`         | no                 | Run dirs of hardened blocks to bind as hard macros                                                         |
| `MACRO_CHANNEL`      | no                 | Gap in µm between adjacent macros; read by the project floorplan file (wider = easier routing, larger die) |
| `FLOORPLAN`          | no                 | Project TCL placing the macros (`place_macro` per instance)                                                |
| `PDN`                | no                 | PDN strategy override (macro runs default to `pdn_macro.tcl`)                                              |

The flow is six stages, each an independent `openroad` process chained through ODB checkpoints: `1_floorplan`, `2_place`, `3_cts`, `4_route`, `5_final`, `6_gds` (KLayout merge). ICG clock gates from synthesis are placed, routed and balanced by CTS.

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`: the layout (`output/design.def/.odb/.gds`), the routed `output/netlist.v` and parasitics `output/netlist.spef` consumed by the `post-pnr-*` flows, the hard-macro abstracts (`output/abstract.lef`, `output/timing_model.lib`), per-stage checkpoints/logs, and the reports (per-stage timing/area, `route_drc.rpt` — must be empty — plus critical paths, WNS/TNS, clock skew, power, design area).

#### Hierarchical place-and-route (hard macros)

1. Harden each block: `make pnr TOP_LEVEL=<block> ... MAX_ROUTE_LAYER=M6` (reserve M7 for the parent's power over the macros; combinational blocks are fine — CTS skips itself).
2. Synthesize the parent with empty stubs: `make syn TOP_LEVEL=<top> BLACKBOX_MODULES="<block> ..." LINK_BLACKBOXES=0 ...`.
3. Implement the parent: `make pnr ... MACRO_DIRS="<block_dir> ..." FLOORPLAN=<file>`, where the file places each macro (`place_macro -macro_name <inst> -location {x y} -orientation R0`).

The `post-pnr-*` steps take the same `MACRO_DIRS`: STA uses the blocks' timing models, simulation compiles their routed netlists, and DPA analyzes the blocks in full — `power_summary.rpt` is the true total and `power_macros.rpt` breaks out each macro's in-system power. Note: `route_drc.rpt` may show a few `Lef58EolKeepOut` markers at macro pins — false positives of the abstract (the merged GDS metal is continuous there).

### Post-place-and-route static timing analysis (OpenSTA)

```bash
make post-pnr-sta TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> [MACRO_DIRS="dir ..."]
```

Same interface and reports as `make post-syn-sta`, but `NETLIST_DIR` points at a `make pnr` run: the routed `netlist.v` is linked and `netlist.spef` is read, so timing is parasitics-accurate with propagated clocks.

### Post-place-and-route gate-level simulation

```bash
make post-pnr-sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> \
    [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1] [MACRO_DIRS="dir ..."]
```

Same interface and testbench conventions as `make post-syn-sim` (including the `POST_SYN_SIM` compile-time flag), but simulates the routed netlist from a `make pnr` run. Pass `VCD=1` to dump the `activity.vcd` consumed by `make post-pnr-dpa`.

### Post-place-and-route dynamic power analysis (OpenSTA)

```bash
make post-pnr-dpa TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> VCD_DIR=<vcd_dir> \
    [TB=<testbench>] [MACRO_DIRS="dir ..."]
```

Same interface as `make post-syn-dpa`, but `NETLIST_DIR` points at a `make pnr` run: the routed netlist and `netlist.spef` are read, so power is parasitics-accurate. With `MACRO_DIRS`, the hardened blocks are analyzed in full and `power_macros.rpt` reports each macro's in-system power.

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

| Parameter            | Make targets                | Values                          | Description                                                                          |
| -------------------- | --------------------------- | ------------------------------- | ------------------------------------------------------------------------------------ |
| `PROJECT`            | all                         | project name                    | Required. Project under `projects/` to operate on (no default)                       |
| `TOP_LEVEL`          | all except init and clean-* | module name                     | RTL module to build/simulate; can be any module in the hierarchy                     |
| `TB`                 | sim, post-*-sim, post-*-dpa | testbench module name           | Testbench to run (default `tb_$(TOP_LEVEL)`)                                         |
| `CLK_PERIOD_NS`      | all except init and clean-* | e.g. `1.0`                      | Clock period in nanoseconds (for `syn`: the ABC delay target, default `1.0`)         |
| `OUT_DIR`            | all except clean-all        | directory name                  | Output subdirectory under `sim/` or `imp/`                                           |
| `NETLIST_DIR`        | pnr, post-syn-*, post-pnr-* | e.g. `top_2x2`                  | Netlist run to consume (`make syn` for pnr/post-syn-*, `make pnr` for post-pnr-*)    |
| `VCD_DIR`            | post-syn-dpa, post-pnr-dpa  | e.g. `pwr_2x2`                  | Directory containing `activity.vcd` from the matching gate-level simulation          |
| `PARAMS`             | sim, syn, post-*-sim        | `"KEY=VAL ..."`                 | Project-specific RTL elaboration parameters                                          |
| `VCD`                | sim, post-*-sim             | `0` (default), `1`              | Enable Verilator tracing and dump `activity.vcd`                                     |
| `KEEP_HIERARCHY`     | syn, post-syn-dpa           | `0` (default), `1`              | Preserve module boundaries in the netlist                                            |
| `KEEP_MODULES`       | syn, post-syn-dpa           | `"mod ..."` (default: `none`)   | Preserve only the listed module boundaries and flatten everything below them         |
| `BLACKBOX_MODULES`   | syn, post-syn-dpa           | `"mod ..."` (default: `none`)   | Do not elaborate the listed modules; link their netlists from an earlier run         |
| `LINK_BLACKBOXES`    | syn                         | `1` (default), `0`              | `0` keeps blackboxed modules as empty stubs for hierarchical P&R                     |
| `CORE_UTIL`          | pnr                         | percent (default: `40`)         | Core utilization for the floorplan; die area derives from it                         |
| `ASPECT_RATIO`       | pnr                         | ratio (default: `1.0`)          | Core height/width ratio                                                              |
| `CORE_MARGIN`        | pnr                         | µm (default: `2`)               | Margin between core area and die edge                                                |
| `PLACE_DENSITY`      | pnr                         | 0–1 (default: `0.60`)           | Global placement target density                                                      |
| `MAX_ROUTE_LAYER`    | pnr                         | layer (default: `M7`)           | Top signal-routing layer; `M6` when hardening a tile reserves M7 for the parent PDN  |
| `CLK_UNCERTAINTY_PS` | pnr                         | ps (default: `0`)               | Clock uncertainty applied to the clocks                                              |
| `PNR_STEP`           | pnr                         | `all` (default) or a stage name | `all` = full clean run; a stage name re-runs that stage from the previous checkpoint |
| `PNR_THREADS`        | pnr                         | `0` (default) or thread count   | OpenROAD thread count; `0` = all cores. Fewer route threads lower the memory peak    |
| `MACRO_DIRS`         | pnr, post-pnr-*             | `"dir ..."` (default: `none`)   | Hardened-block run dirs to bind as hard macros                                       |
| `MACRO_CHANNEL`      | pnr                         | µm (default: `10`)              | Gap between adjacent macros, used by the project floorplan file                      |
| `FLOORPLAN`          | pnr                         | path (default: `none`)          | Project-owned macro-placement TCL sourced after the floorplan                        |
| `PDN`                | pnr                         | path (default: `none`)          | PDN strategy override (macro runs default to `scripts/pnr/pdn_macro.tcl`)            |
