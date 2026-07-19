---
name: add-project
description: Scaffold a new empty RTL project under projects/<name>/ so it can be populated with custom RTL and testbenches. Use when the user wants to create/add a new project, start a new design from scratch, or set up a fresh project skeleton in this repo.
---

# Add a new project

Create an empty project skeleton under `projects/<name>/` that plugs into the shared EDA flow. The user populates `rtl/` and `tb/` afterwards.

## 1. Resolve the project name

The project name comes from the skill invocation (e.g. `/add-project my-accel`).

- If no name was given, ask the user for one.
- Require a lowercase kebab-case name (letters, digits, hyphens), matching the existing convention (e.g. `ai-core`).
- Abort if `projects/<name>/` already exists — report it and stop.

Use `<name>` below to mean the resolved name.

## 2. Create the directory skeleton

If this is a sparse checkout (`git config core.sparseCheckout` returns `true`), first add the new project to the checkout cone so the files you are about to create fall inside the sparse set and git tracks them:

```bash
git sparse-checkout add projects/<name>
```

Skip this in a full clone — running `git sparse-checkout add` there would switch the clone into sparse mode and hide the other projects.

Create these directories under `projects/<name>/`:

```
rtl/                # SystemVerilog source modules
tb/                 # Verilator testbenches
scripts/            # Project-specific scripts (sweeps, generators) — left empty
doc/diagrams/       # Block diagrams
doc/formulas/       # Mathematical formulas
doc/charts/         # Charts and their generator scripts (generated)
doc/data/           # Extracted results (generated)
```

Add an empty `.gitkeep` file inside each of `rtl/`, `tb/`, `scripts/`, `doc/diagrams/`, `doc/formulas/`, `doc/charts/`, and `doc/data/` so git tracks the otherwise-empty folders.

Do NOT scaffold any design-specific automation (no sweep/generator scripts) — `scripts/` is intentionally left empty for the user to populate. When the user later adds experiments, each is a plain, self-contained script placed directly under `scripts/` (e.g. a synthesis/sim sweep) that writes its results into `doc/data/` and its charts into `doc/charts/`; these are **run directly** (`bash`, `python`), not through `make` targets.

## 3. Create the generated output dirs

Run, from the repository root with the environment sourced:

```bash
source sourceme.sh
make init PROJECT=<name>
```

This creates `projects/<name>/sim/` and `projects/<name>/imp/`. These stay gitignored (`projects/*/sim`, `projects/*/imp`) and need no `.gitkeep`.

## 4. Write a stub project README

Create `projects/<name>/README.md` with this skeleton (fill the title; leave the tables/sections as placeholders for the user to populate):

```markdown
# <Name>

<One-line description of the project.>

This project plugs into the repository-level EDA flow. See the [root README](../../README.md) for the `make` targets, their generic parameters, and the typical pipeline. This document covers the parts specific to `<name>`.

## Quick start

\`\`\`bash
source ../../sourceme.sh   # or: source sourceme.sh from the repository root

make sim PROJECT=<name> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<out_dir>
\`\`\`

`<name>` is selected with `PROJECT=<name>` on every `make` command.

## Top-level modules

_None yet. Add RTL to `rtl/` and a testbench `tb/tb_<top_level>.sv` per top-level._

## RTL elaboration parameters

_None yet._

## Testbenches

_None yet._

## Experiments (automation scripts)

_None yet. Add scripts directly under `scripts/` (run directly); they write results to `doc/data/` and charts to `doc/charts/`._
```

Render the title `<Name>` as a readable form of the project name (e.g. `my-accel` → `My-Accel`).

## 5. Register the project in the root README

Add a bullet for the new project to the `Projects:` list in the root `README.md`, mirroring the existing `ai-core` entry:

```markdown
- [`<name>`](projects/<name>/README.md) — <one-line description>.
```

## 6. Report

Tell the user:
- The skeleton that was created.
- That `sim/` and `imp/` are generated and gitignored.
- To add RTL modules to `projects/<name>/rtl/` and testbenches to `projects/<name>/tb/`, then build with `make <target> PROJECT=<name> ...`.

Do not commit anything unless the user asks.
