# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. See [README.md](README.md) for the shared EDA flow (commands, make parameters, pipeline). For a project's designs, top-levels, RTL parameters, and module reference, see that project's own README at `projects/<name>/README.md`.

## Layout

This is a multi-project RTL sandbox.

- `scripts/` — project-agnostic EDA flow wrappers (`sim`, `syn`, `post-syn-{sta,sim,dpa}`).
- `projects/<name>/` — one RTL project; contains `rtl/`, `tb/`, `sim/`, `imp/`, `doc/`, and `scripts/flow/` (project-specific automation).
- Select a project with `make <target> PROJECT=<name>`; `PROJECT` is required (no default) and so is `TOP_LEVEL`. The available projects are listed in [README.md](README.md).

## Simulation

`make sim` is the simulation flow: Verilator `--binary --timing`, with a self-contained SV testbench (`tb/tb_<top>.sv`) as the top module. This is what `syn` and the post-syn flows build on.

**Naming:** the `_sc` suffix on RTL/top-levels (e.g. `top_bas_4x8_sc`) denotes a *split-cell design variant* — it is part of the design, not a separate flow.

## Partial / sparse clones

The repo supports partial clone + sparse-checkout (see the README "Cloning" section), so **a working copy may contain only a subset of `projects/*`** — sometimes none. Do not assume every project is present: never glob `projects/*` expecting it to be exhaustive, and check the project directory exists before operating on it. The `Projects:` list in the root README is the authoritative catalog of what exists. To work on a project that is not checked out, materialize it with `git sparse-checkout add projects/<name>`.

## Environment

Always source the environment script before running any command:

```bash
source sourceme.sh
```

This sets `CODE_HOME` (the parent of this repo) and the paths for Verilator, Yosys, Yosys-Slang, OpenSTA, and OpenROAD. Paths inside the flow are resolved as `$CODE_HOME/ai-core/projects/$PROJECT/...`.
