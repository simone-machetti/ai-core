# AI Core

Multi-project sandbox for prototyping RTL designs, built around the `ai-core` design project. The flow (Verilator simulation, Yosys synthesis, OpenSTA timing & dynamic power) is project-agnostic and lives at the repository root; each design sits under `projects/<name>/`, so additional projects can be added later without touching the shared flow.

Projects:

- [`ai-core`](projects/ai-core/README.md) — next-generation AI-Core architecture (clean redesign, in progress).
- [`ai-core-legacy`](projects/ai-core-legacy/README.md) — fixed-point multiply-accumulate Processing Elements (PEs) for AI/ML inference. The original reference design.

This README documents the shared EDA flow: the `make` targets, their parameters, and the typical pipeline. For a project's designs, top-levels, RTL parameters, and experiments, see that project's own README.

## Cloning — selecting projects

This is a multi-project repo, but you don't have to download every project. A **partial clone** (`--filter=blob:none`) skips file contents until you check them out, and **sparse-checkout** controls which `projects/<name>/` directories land in your working tree. The shared tooling — the top-level files — is always included. Pick one of the options below; consult the `Projects:` list above for the `<name>` of each project.

> Your git host must support partial clone (`uploadpack.allowFilter=true`). GitHub and GitLab enable it by default.

### One project

```bash
git clone --filter=blob:none --no-checkout <repo-url> ai-core
cd ai-core
git sparse-checkout init --cone
git sparse-checkout set scripts projects/<name>
git checkout main
```

### Multiple projects

List every project you want after `scripts` (space-separated):

```bash
git clone --filter=blob:none --no-checkout <repo-url> ai-core
cd ai-core
git sparse-checkout init --cone
git sparse-checkout set scripts projects/<name-1> projects/<name-2>
git checkout main
```

### No project (shared tooling only)

Use this to start a brand-new project, or when you only need the flow scripts. `projects/` stays empty until you create or add one.

```bash
git clone --filter=blob:none --no-checkout <repo-url> ai-core
cd ai-core
git sparse-checkout init --cone
git sparse-checkout set scripts
git checkout main
```

### All projects

A normal full clone gives you everything:

```bash
git clone <repo-url> ai-core
cd ai-core
```

### Changing your selection later

No re-clone needed — adjust the working set at any time (files are fetched on demand):

```bash
git sparse-checkout add projects/<name>         # add another project to the current set
git sparse-checkout set scripts projects/<name> # replace the whole selection
git sparse-checkout list                        # show what is currently checked out
git sparse-checkout disable                     # materialize all projects (switch to full)
```

The `Projects:` list at the top of this README is the catalog of everything that exists — including projects you have not checked out — and is the one shared file every new project edits, so it is where collaborators coordinate.

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
│       ├── scripts/      # Project-specific scripts
│       │   └── flow/     # End-to-end automation (one subfolder per experiment)
│       ├── doc/          # Documentation and results
│       │   ├── diagrams/ # Block diagrams
│       │   ├── formulas/ # Mathematical formulas
│       │   ├── charts/   # Comparison charts (<exp>/<chart>.png, generated)
│       │   └── data/     # Extracted results (<exp>/results.xlsx, generated)
│       ├── sim/          # Simulation outputs (generated)
│       └── imp/          # Synthesis/STA/DPA outputs (generated)
├── Makefile              # Build system entry point (PROJECT=<name> selects project)
├── sourceme.sh           # Environment setup (sources ~/.bashrc, derives REPO_HOME)
└── CLAUDE.md             # AI assistant guidance for this repository
```

All `make` targets require `PROJECT=<name>` to select the project they operate on (there is no default; targets fail fast if it is unset or names a project that is not in your checkout). The flow scripts in `scripts/` resolve project-specific paths through the `SEL_PROJECT` env var exported by the Makefile.

## Environment setup

Tool and PDK install locations are **per-user**: you declare them in your `~/.bashrc`, and `sourceme.sh` sources that file and derives the rest. Run this once per shell before any `make` command:

```bash
source sourceme.sh
```

`sourceme.sh` sets `REPO_HOME` from its own location, sources `~/.bashrc`, then derives `ASAP7_HOME` from `PDK_HOME`. You therefore export only the install **roots** in your `~/.bashrc` — the shared flow itself is project- and machine-agnostic:

| Variable | Purpose |
| --- | --- |
| `EDA_HOME` | Root holding the EDA tool installs. |
| `VERILATOR_HOME`, `YOSYS_HOME`, `YOSYS_SLANG_HOME`, `OPENSTA_HOME` | Per-tool install dirs (conventionally `$EDA_HOME/<tool>`); each tool's `bin/` must be on `PATH`. |
| `PDK_HOME` | Root holding the PDK trees — the ASAP7 standard-cell liberty (`.lib`) and verilog (`.v`) consumed by synthesis, STA, DPA and post-synthesis simulation. |

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

1. `make sim` — functional verification; produces `activity.vcd`.
2. `make syn` — logic synthesis; produces the netlist consumed by all post-synthesis flows.
3. `make post-syn-sim` — gate-level functional verification; produces `activity.vcd` consumed by `make post-syn-dpa`.
4. `make post-syn-sta` — static timing analysis from the synthesized netlist.
5. `make post-syn-dpa` — power estimation using the synthesized netlist and the `activity.vcd` from `make post-syn-sim`.

## Skills

This repository ships [Claude Code](https://claude.com/claude-code) skills under [.claude/skills/](.claude/skills/). They automate the repetitive parts of working in this sandbox — scaffolding a new project. Invoke a skill by name (e.g. `/add-project my-accel`) in a Claude Code session.

| Skill                                                | Purpose                                                                                                                                                                                                                               |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`add-project`](.claude/skills/add-project/SKILL.md) | Scaffold a new empty project under `projects/<name>/`: creates the `rtl/`, `tb/`, `scripts/flow/`, and `doc/` skeleton, runs `make init`, writes a stub project README, and registers the project in this README's `Projects:` list.  |

A typical greenfield flow is `/add-project` to create the skeleton, then populate `rtl/` and `tb/` to verify, characterize, and document the design.

## Commands

The `TOP_LEVEL` values and `PARAMS` keys are project-specific; the syntax below is the shared interface. See the project README for the available top-levels and elaboration parameters.

### Pre-synthesis simulation (Verilator)

```bash
make sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> [PARAMS="KEY=VAL ..."]
```

| Parameter       | Required | Description                                 |
| --------------- | -------- | ------------------------------------------- |
| `TOP_LEVEL`     | yes      | RTL module to simulate                      |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                 |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`            |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`, including an `activity.vcd` waveform.

### Logic synthesis (Yosys + ABC, ASAP7 target)

```bash
make syn TOP_LEVEL=<top_level> OUT_DIR=<name> [PARAMS="KEY=VAL ..."] [KEEP_HIERARCHY=1]
```

| Parameter        | Required        | Description                                                  |
| ---------------- | --------------- | ------------------------------------------------------------ |
| `TOP_LEVEL`      | yes             | RTL module to synthesize; can be any module in the hierarchy |
| `OUT_DIR`        | yes             | Output subdirectory under `imp/`                             |
| `PARAMS`         | no              | Project-specific RTL elaboration parameters                  |
| `KEEP_HIERARCHY` | no (default: 0) | Preserve module boundaries in the netlist (skips `flatten`)  |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`.

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
make post-syn-sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> [PARAMS="KEY=VAL ..."]
```

| Parameter       | Required | Description                                                  |
| --------------- | -------- | ------------------------------------------------------------ |
| `TOP_LEVEL`     | yes      | RTL module to simulate                                       |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                  |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`                             |
| `NETLIST_DIR`   | yes      | Directory containing the synthesized netlist from `make syn` |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters                  |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`. Compiles the testbench with the `POST_SYNTH` compile-time flag to instantiate the flattened gate-level netlist instead of the RTL.

### Post-synthesis dynamic power analysis (OpenSTA)

```bash
make post-syn-dpa TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> VCD_DIR=<vcd_dir> [KEEP_HIERARCHY=1]
```

| Parameter        | Required        | Description                                                                                     |
| ---------------- | --------------- | ----------------------------------------------------------------------------------------------- |
| `TOP_LEVEL`      | yes             | RTL module name                                                                                 |
| `CLK_PERIOD_NS`  | yes             | Clock period in nanoseconds                                                                     |
| `OUT_DIR`        | yes             | Output subdirectory under `imp/`                                                                |
| `NETLIST_DIR`    | yes             | Directory containing the synthesized netlist from `make syn`                                    |
| `VCD_DIR`        | yes             | Directory containing `activity.vcd` from `make post-syn-sim`                                    |
| `KEEP_HIERARCHY` | no (default: 0) | Also generate `power_hierarchy.rpt` with per-instance breakdown (requires hierarchical netlist) |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`.

### Experiment automation

Each project keeps its end-to-end automation under `projects/<PROJECT>/scripts/flow/`, with **one subfolder per experiment**. By convention every experiment folder provides the same trio of scripts, which the generic `flow-*` targets drive:

| Script   | Target           | Purpose                                          |
| -------- | ---------------- | ------------------------------------------------ |
| `run.py` | `make flow-run`  | Run the experiment (drives the `make` flow)      |
| `ext.py` | `make flow-ext`  | Extract results from the run outputs             |
| `gen.py` | `make flow-gen`  | Generate charts/tables from the extracted data   |

Select the experiment with `EXP=<experiment>` (required — there is no default):

```bash
make flow-list                 # list the experiments available in the project
make flow-run EXP=<experiment> # then flow-ext / flow-gen
```

Experiments are project-specific; see the project's own README for what each one does. The targets fail fast if `EXP` is unset or names an experiment the project doesn't have.

### Cleanup

```bash
make clean-sim OUT_DIR=<name> # remove one simulation run
make clean-imp OUT_DIR=<name> # remove one synthesis/STA/DPA run
make clean-all                # remove all sim/ and imp/ directories
```

### Make-level parameters reference

| Parameter        | Make targets                                       | Values                          | Description                                                       |
| ---------------- | -------------------------------------------------- | ------------------------------- | ----------------------------------------------------------------- |
| `PROJECT`        | all                                                | project name                    | Required. Project under `projects/` to operate on (no default)    |
| `TOP_LEVEL`      | sim, syn, post-syn-sta, post-syn-sim, post-syn-dpa | module name                     | RTL module to build/simulate; can be any module in the hierarchy  |
| `CLK_PERIOD_NS`  | sim, post-syn-sta, post-syn-sim, post-syn-dpa      | e.g. `1.0`                      | Clock period in nanoseconds                                       |
| `OUT_DIR`        | all except clean-all                               | directory name                  | Output subdirectory under `sim/` or `imp/`                        |
| `NETLIST_DIR`    | post-syn-sta, post-syn-sim, post-syn-dpa           | e.g. `top_bas_4x8_syn`          | Directory containing the synthesized netlist from `make syn`      |
| `VCD_DIR`        | post-syn-dpa                                       | e.g. `top_bas_4x8_post-syn-sim` | Directory containing `activity.vcd` from `make post-syn-sim`      |
| `PARAMS`         | sim, syn, post-syn-sim                             | `"KEY=VAL ..."`                 | Project-specific RTL elaboration parameters                       |
| `KEEP_HIERARCHY` | syn, post-syn-dpa                                  | `0` (default), `1`              | Preserve module boundaries in the netlist                         |
| `EXP`            | flow-run, flow-ext, flow-gen                       | experiment name                 | Required. Experiment subfolder under `scripts/flow/` (no default) |
