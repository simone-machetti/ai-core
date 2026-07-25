# ASIC flow overview

This is the entry point of the learn-asic-flow course: a complete, code-grounded walk through the ASIC implementation flow of this repository — from RTL to a routed, power-analyzed layout in ASAP7. This document gives the map: what the flow is, how the pieces connect, the repository conventions every later document relies on, and how to read the course.

## The pipeline

```
rtl -> sim
rtl -> syn -> netlist -> post-syn-sim / post-syn-sta / post-syn-dpa
              netlist -> pnr -> layout + routed netlist + spef
                             -> post-pnr-sim / post-pnr-sta / post-pnr-dpa
```

Every step is a `make` target. In pipeline order:

1. **`make sim`** — pre-synthesis functional simulation with Verilator. Verifies the RTL against a self-checking testbench; optionally dumps switching activity (`activity.vcd`).
2. **`make syn`** — logic synthesis with Yosys (yosys-slang frontend, ABC mapper) into the ASAP7 standard-cell library. Produces the gate-level `netlist.v` that everything downstream consumes.
3. **`make post-syn-sim` / `post-syn-sta` / `post-syn-dpa`** — the three post-synthesis analyses: gate-level simulation (Verilator), static timing analysis (OpenSTA, ideal wires), and VCD-based dynamic power analysis (OpenSTA).
4. **`make pnr`** — place-and-route with OpenROAD, six stages from the synthesized netlist to the final layout: floorplan, placement, clock-tree synthesis, routing, finishing, GDS merge (KLayout). Produces the layout (`design.def/.odb/.gds`), the routed `netlist.v`, extracted parasitics (`netlist.spef`), and the hard-macro abstracts (`abstract.lef`, `timing_model.lib`) that enable hierarchical implementation.
5. **`make post-pnr-sim` / `post-pnr-sta` / `post-pnr-dpa`** — the same three analyses on the routed design, now parasitics-accurate: real wire RC from the SPEF and propagated (real) clock trees.

Two properties make the flow composable:

- **The netlist contract**: every netlist producer writes `imp/<OUT_DIR>/output/netlist.v` and every netlist consumer reads `imp/<NETLIST_DIR>/output/netlist.v`. A P&R run dir therefore plugs into the same analysis steps as a synthesis run dir.
- **The hierarchical loop**: a completed P&R run is itself consumable as a *hard macro* by a later P&R run (`MACRO_DIRS`), which is how designs too large for flat implementation are built ([18_hierarchical.md](18_hierarchical.md)).

## Tools and technology

| Tool                | Role                                    | Steps                  |
| ------------------- | --------------------------------------- | ---------------------- |
| Verilator           | RTL and gate-level simulation           | sim, post-*-sim        |
| Yosys + yosys-slang | SystemVerilog elaboration and synthesis | syn                    |
| ABC (inside Yosys)  | Technology mapping to standard cells    | syn                    |
| OpenROAD            | Place-and-route (all six stages)        | pnr                    |
| OpenSTA             | Static timing and power analysis        | post-*-sta, post-*-dpa |
| KLayout             | Final GDS merge and layout viewing      | pnr (6_gds)            |

The technology is **ASAP7**: a 7 nm predictive, academic PDK (`asap7sc7p5t` — 7.5-track cells, RVT flavor, TT corner in this flow). It is packaged inside the OpenROAD-flow-scripts platform tree (`$ASAP7_HOME`), from which the flow takes liberty files, LEFs, GDS, and physical-setup scripts. [01_technology.md](01_technology.md) dissects all of it. The implementation style is **block-level**: pins on routing layers, no pad ring, single power domain — the standard style for IP blocks that integrate into a larger die.

## Repository conventions

These conventions appear in every script and every later document:

- **Make parameters → `SEL_*` environment variables.** The Makefile exports each parameter (`PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR`, ...) as `SEL_<NAME>`, and flow scripts read only those plus `REPO_HOME`/`ASAP7_HOME`. The flow hardcodes no project or repo name.
- **Run directories.** Every run lands in `projects/<PROJECT>/imp/<OUT_DIR>/` (or `sim/<OUT_DIR>/` for simulations) with exactly two subdirectories: `output/` (products and tool logs) and `report/` (reports). Every `make` target starts by deleting its own `OUT_DIR` — runs are always clean and reproducible.
- **Time is in picoseconds.** The ASAP7 liberty files use ps, so OpenSTA and OpenROAD operate in ps throughout. The user-facing `CLK_PERIOD_NS` is converted once (`× 1000`) in each script.
- **The clock is `clk_i`.** All constraint generation targets the port `clk_i` when it exists; designs without it are treated as combinational ([02_constraints.md](02_constraints.md)).
- **All flow code is in-repo** (`scripts/`). Files from the ASAP7 platform are *sourced* when they are pure data (`make_tracks.tcl`, PDN strategies, `setRC.tcl`) and *inlined* into our scripts when they depend on ORFS-specific variables.

## The course

Reading order and scope of each document:

| File                                       | Content                                                               |
| ------------------------------------------ | --------------------------------------------------------------------- |
| [00_overview.md](00_overview.md)           | This document                                                         |
| [01_technology.md](01_technology.md)       | PDK anatomy: liberty, LEF, GDS, corners, VT flavors, ASAP7 specifics  |
| [02_constraints.md](02_constraints.md)     | SDC theory; the shared clock + virtual-clock + hold-false-path scheme |
| [03_sim.md](03_sim.md)                     | Pre-synthesis simulation                                              |
| [04_syn.md](04_syn.md)                     | Synthesis: elaboration, mapping, hierarchy modes                      |
| [05_post_syn_sim.md](05_post_syn_sim.md)   | Gate-level simulation, cell models                                    |
| [06_post_syn_sta.md](06_post_syn_sta.md)   | Static timing analysis                                                |
| [07_post_syn_dpa.md](07_post_syn_dpa.md)   | Dynamic power analysis, VCD annotation                                |
| [08_pnr_overview.md](08_pnr_overview.md)   | P&R architecture: stages, checkpoints, helpers, plumbing              |
| [09_pnr_floorplan.md](09_pnr_floorplan.md) | Floorplan: die/core, rows, tracks, pins, tie/tap cells, power grid    |
| [10_pnr_place.md](10_pnr_place.md)         | Global and detailed placement, design repair                          |
| [11_pnr_cts.md](11_pnr_cts.md)             | Clock-tree synthesis                                                  |
| [12_pnr_route.md](12_pnr_route.md)         | Global and detailed routing                                           |
| [13_pnr_final.md](13_pnr_final.md)         | Fillers, RC extraction, final products                                |
| [14_pnr_gds.md](14_pnr_gds.md)             | The GDS merge                                                         |
| [15_post_pnr_sim.md](15_post_pnr_sim.md)   | Gate-level simulation of the routed netlist                           |
| [16_post_pnr_sta.md](16_post_pnr_sta.md)   | Parasitics-accurate timing analysis                                   |
| [17_post_pnr_dpa.md](17_post_pnr_dpa.md)   | Parasitics-accurate power analysis, full-view hierarchical mode       |
| [18_hierarchical.md](18_hierarchical.md)   | The hard-macro flow across synthesis, P&R and analyses                |
| [19_knobs.md](19_knobs.md)                 | Cross-reference of every knob: default, range, effect, tradeoffs      |

## How to read

Every document follows the same template: **Inputs and outputs** (position in the pipeline, files consumed and produced) → **Theory** (the step in any ASIC flow, terms defined from scratch) → **Implementation walkthrough** (the scripts quoted verbatim, block by block — no code skipped) → **Design space** (alternatives to each decision and their implications) → **Knobs** (what can be tuned, in which direction each tradeoff moves) → **Notes and caveats** (flow-specific facts, pitfalls and known artifacts) → **Commercial perspective** (what the step is called in commercial flows, where useful).

Two companions while reading:

- `scripts/asic_flow.md` — the compact per-step inputs/outputs/parameters reference.
- `README.md` — the full command reference.
