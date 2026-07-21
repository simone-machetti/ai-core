# AI Core

Multi-project sandbox for prototyping RTL designs, built around the `ai-core` design project. The flow (Verilator simulation, Yosys synthesis, OpenSTA timing & dynamic power) is project-agnostic and lives at the repository root; each design sits under `projects/<name>/`, so additional projects can be added later without touching the shared flow.

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
make syn PROJECT=<project> TOP_LEVEL=<top_level> OUT_DIR=<name>

# Post-synthesis gate-level simulation
make post-syn-sim PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-synthesis static timing analysis
make post-syn-sta PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-synthesis dynamic power analysis
make post-syn-dpa PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name> VCD_DIR=<name>
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
│   ├── post-syn-sta/     # Post-synthesis static timing analysis flow
│   │   └── run.tcl       # OpenSTA timing analysis script
│   ├── post-syn-sim/     # Post-synthesis gate-level simulation flow
│   │   ├── run.sh        # Verilator compile and run script
│   │   └── filelist.f    # Gate-level netlist and cell library filelist
│   └── post-syn-dpa/     # Post-synthesis dynamic power analysis flow
│       └── run.tcl       # OpenSTA power analysis script
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
│       └── imp/          # Synthesis/STA/DPA outputs (generated)
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
| `VERILATOR_HOME`, `YOSYS_HOME`, `YOSYS_SLANG_HOME`, `OPENSTA_HOME` | Per-tool install dirs (conventionally `$EDA_HOME/<tool>`); each tool's `bin/` must be on `PATH`.                                                        |
| `PDK_HOME`                                                         | Root holding the PDK trees — the ASAP7 standard-cell liberty (`.lib`) and verilog (`.v`) consumed by synthesis, STA, DPA and post-synthesis simulation. |

A minimal `~/.bashrc` block — add this and adjust the two roots (`EDA_HOME` and `PDK_HOME`) to your machine:

```bash
# --- EDA tool binaries ---
export EDA_HOME=/opt/eda
export VERILATOR_HOME=$EDA_HOME/verilator
export YOSYS_HOME=$EDA_HOME/yosys
export YOSYS_SLANG_HOME=$EDA_HOME/yosys-slang
export OPENSTA_HOME=$EDA_HOME/opensta
export PATH=$VERILATOR_HOME/bin:$YOSYS_HOME/bin:$YOSYS_SLANG_HOME/bin:$OPENSTA_HOME/bin:$PATH

# --- PDK ---
export PDK_HOME=/opt/pdks
```

Notes:

- **Do not** set `REPO_HOME` — `sourceme.sh` derives it from its own location, so the repo works unchanged if renamed or reused for a different project.
- `ASAP7_HOME` defaults to `$PDK_HOME/OpenROAD-flow-scripts/flow/platforms/asap7`; export it in `~/.bashrc` to target a different platform/technology.

## Typical workflow

The make targets form a pipeline where earlier steps produce artifacts consumed by later ones:

1. `make sim` — functional verification (pass `VCD=1` to also dump `activity.vcd`).
2. `make syn` — logic synthesis; produces the netlist consumed by all post-synthesis flows.
3. `make post-syn-sim` — gate-level functional verification; produces `activity.vcd` consumed by `make post-syn-dpa`.
4. `make post-syn-sta` — static timing analysis from the synthesized netlist.
5. `make post-syn-dpa` — power estimation using the synthesized netlist and the `activity.vcd` from `make post-syn-sim`.

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
make syn TOP_LEVEL=<top_level> OUT_DIR=<name> [PARAMS="KEY=VAL ..."] [KEEP_HIERARCHY=1] \
    [KEEP_MODULES="mod ..."] [BLACKBOX_MODULES="mod ..."]
```

| Parameter          | Required        | Description                                                                  |
| ------------------ | --------------- | ---------------------------------------------------------------------------- |
| `TOP_LEVEL`        | yes             | RTL module to synthesize; can be any module in the hierarchy                 |
| `OUT_DIR`          | yes             | Output subdirectory under `imp/`                                             |
| `PARAMS`           | no              | Project-specific RTL elaboration parameters                                  |
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
make clean-imp OUT_DIR=<name> # remove one synthesis/STA/DPA run
make clean-all                # remove all sim/ and imp/ directories
```

### Make-level parameters reference

| Parameter          | Make targets                                       | Values                          | Description                                                                                |
| ------------------ | -------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------ |
| `PROJECT`          | all                                                | project name                    | Required. Project under `projects/` to operate on (no default)                             |
| `TOP_LEVEL`        | sim, syn, post-syn-sta, post-syn-sim, post-syn-dpa | module name                     | RTL module to build/simulate; can be any module in the hierarchy                           |
| `TB`               | sim, post-syn-sim, post-syn-dpa                    | testbench module name           | Testbench to run (default `tb_$(TOP_LEVEL)`); set it to use an alternative bench           |
| `CLK_PERIOD_NS`    | sim, post-syn-sta, post-syn-sim, post-syn-dpa      | e.g. `1.0`                      | Clock period in nanoseconds                                                                |
| `OUT_DIR`          | all except clean-all                               | directory name                  | Output subdirectory under `sim/` or `imp/`                                                 |
| `NETLIST_DIR`      | post-syn-sta, post-syn-sim, post-syn-dpa           | e.g. `top_bas_4x8_syn`          | Directory containing the synthesized netlist from `make syn`                               |
| `VCD_DIR`          | post-syn-dpa                                       | e.g. `top_bas_4x8_post-syn-sim` | Directory containing `activity.vcd` from `make post-syn-sim`                               |
| `PARAMS`           | sim, syn, post-syn-sim                             | `"KEY=VAL ..."`                 | Project-specific RTL elaboration parameters                                                |
| `VCD`              | sim, post-syn-sim                                  | `0` (default), `1`              | Enable Verilator tracing and dump `activity.vcd` (off by default; costly on large designs) |
| `KEEP_HIERARCHY`   | syn, post-syn-dpa                                  | `0` (default), `1`              | Preserve module boundaries in the netlist                                                  |
| `KEEP_MODULES`     | syn, post-syn-dpa                                  | `"mod ..."` (default: `none`)   | Preserve only the listed module boundaries and flatten everything below them               |
| `BLACKBOX_MODULES` | syn, post-syn-dpa                                  | `"mod ..."` (default: `none`)   | Do not elaborate the listed modules; link their netlists from `imp/<mod>/output/netlist.v` |
