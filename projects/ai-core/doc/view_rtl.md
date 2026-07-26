# Viewing RTL schematics with sv-pathfinder — setup task

Task/prompt for a fresh chat: **add support for visualizing the schematics of the ai-core
SystemVerilog RTL** directly in the editor, using the *sv-pathfinder* extension. The only goal is
schematic visualization of the RTL (no waveform integration required). Follow the steps below;
verify each one rather than assuming, since the environment facts were captured on 2026-07-26 and
the extension is young (v0.3.0).

**Extension repo:** https://github.com/heyfey/sv-pathfinder
- Getting started: https://github.com/heyfey/sv-pathfinder/blob/main/GETTING_STARTED.md
- Schematic viewer: https://github.com/heyfey/sv-pathfinder/blob/main/SCHEMATIC.md
- Open VSX (Cursor's default marketplace): `heyfey.sv-pathfinder`

---

## 1. Environment (verified facts, re-check if stale)

- Editor is **Cursor 3.7.21** (VS Code base ~1.113; the extension needs `engines.vscode ^1.93.0` — satisfied). Because it's Cursor, install extensions from **Open VSX**, not the MS Marketplace.
- RTL lives in [projects/ai-core/rtl/](../rtl/) as `*.sv` (SystemVerilog).
- Yosys: `/my_tools/yosys/bin/yosys` (0.62+9). **It does NOT have `read_slang` built in.**
- slang frontend is a **separate plugin**: `/my_tools/yosys-slang/bin/slang.so`, loaded in the syn
  flow via `plugin -i $YOSYS_SLANG_HOME/bin/slang.so` (see [scripts/syn/compile.tcl:13](../../../scripts/syn/compile.tcl#L13)). `YOSYS_SLANG_HOME` resolves to `/my_tools/yosys-slang`.
- Syn collects RTL as **every `*.sv` under `rtl/`, compiled single-unit** (see [scripts/syn/compile.tcl:28](../../../scripts/syn/compile.tcl#L28) and `:69`), include dirs passed as `-I`.
- **Surelog is not installed** (`/my_tools` has: openroad, opensta, systemc, verilator, yosys, yosys-slang) → use the default **slang-server** navigation backend.
- Always `source sourceme.sh` before running flow commands.

## 2. How the extension works (mental model)

sv-pathfinder uses **two independent toolchains** — keep them straight:

1. **Design navigation / hierarchy** — parses a `.f` filelist with the **slang-server** LSP
   (default) or Surelog, selected by `sv-pathfinder.compiler`. This builds the browsable tree.
2. **Schematic rendering** — runs **Yosys + the slang frontend** (`read_slang`) on the selected
   scope. Yosys is located via `sv-pathfinder.ossCadSuitePath` (a directory containing `bin/yosys`)
   or from `PATH`. The extension expects slang to be **built into** Yosys (OSS CAD Suite style);
   there is **no setting to point at a slang `.so` plugin** — this is the one wrinkle for our setup.

End-to-end flow: **Open Design → pick `.f` → browse hierarchy → right-click a scope → Show Schematic.**

## 3. Install the extensions (Open VSX, in Cursor)

```bash
cursor --install-extension heyfey.sv-pathfinder                 # the extension itself
cursor --install-extension Hudson-River-Trading.vscode-slang    # slang-server: default nav backend
# lramseyer.vaporview  # optional waveform companion — NOT needed for schematics, skip
```

Or via the Extensions panel (search the IDs above). Both are confirmed present on Open VSX.

## 4. Give the extension a Yosys that has `read_slang` (the key step)

Our Yosys loads slang as a plugin, but the extension calls `read_slang` directly. Bridge this with a
tiny wrapper that injects the plugin at startup with `yosys -m` (verified: `yosys -m .../slang.so`
makes `read_slang` available on this build), then point `ossCadSuitePath` at a dir whose `bin/yosys`
is that wrapper.

Create `projects/ai-core/scripts/oss-cad-shim/bin/yosys`:

```bash
#!/usr/bin/env bash
# sv-pathfinder expects a Yosys with read_slang built in (OSS CAD Suite style).
# Ours loads slang as a plugin, so load it at startup with -m and pass everything through.
exec /my_tools/yosys/bin/yosys -m "${YOSYS_SLANG_HOME:-/my_tools/yosys-slang}/bin/slang.so" "$@"
```

Then:

```bash
chmod +x projects/ai-core/scripts/oss-cad-shim/bin/yosys
# sanity check — should print the read_slang usage, not "No such command":
projects/ai-core/scripts/oss-cad-shim/bin/yosys -p "help read_slang"
```

Set `sv-pathfinder.ossCadSuitePath` to the **absolute** path of `.../scripts/oss-cad-shim` (the dir
that *contains* `bin/`, not `bin/yosys` itself).

- Before trusting the wrapper, **inspect how the extension actually invokes yosys**: look under
  `~/.cursor/extensions/heyfey.sv-pathfinder-*/` (grep for `yosys`, `read_slang`, `ossCadSuite`). If
  it expects more of the OSS CAD Suite environment (e.g. `LD_LIBRARY_PATH`, other `bin/` tools),
  extend the wrapper or symlink the extra binaries into the shim `bin/`.
- **Simpler alternative** if the wrapper misbehaves: install the real
  [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (bundles an integrated yosys-slang)
  and point `ossCadSuitePath` at it. Downside: a second, possibly different yosys/slang version than
  `make syn` uses. The wrapper keeps schematic elaboration on the *same* toolchain as synthesis.

## 5. Create a `.f` filelist for the design

The navigation backend needs a self-contained `.f` filelist. Mirror exactly what syn feeds Yosys —
all `*.sv` under `rtl/` (single compilation unit means any top's dependencies are all present):

```bash
source sourceme.sh
mkdir -p "$REPO_HOME/projects/ai-core/scripts/view"
find "$REPO_HOME/projects/ai-core/rtl" -name '*.sv' | sort \
  > "$REPO_HOME/projects/ai-core/scripts/view/ai-core.f"
```

Filelist notes:
- One absolute path per line keeps it self-contained (the filelist's own dir and each source file's
  dir are also searched automatically).
- If any RTL uses `` `include ``, add the header dirs — either as `+incdir+<dir>` lines in the `.f`,
  or via the `sv-pathfinder.schematicIncludeDirs` setting (passed to Yosys as `-I`/`-y`). The current
  ai-core RTL compiles with no extra include dirs in syn, so this is likely empty.
- The **top** is chosen later in the hierarchy view, not in the `.f`. Good scopes to open first:
  `pe`, `pe_array`, or `top_dummy` (see [projects/ai-core/rtl/](../rtl/)).
- Confirm the exact accepted `.f` syntax against GETTING_STARTED.md / SCHEMATIC.md if parsing fails.

## 6. Configure settings

Add to the workspace `.vscode/settings.json` (paths must be **absolute** — Cursor does not expand
`$REPO_HOME` in settings):

```jsonc
{
  "sv-pathfinder.compiler": "slang-server",
  "sv-pathfinder.ossCadSuitePath": "/home/simone/work/my_code/ai-core/projects/ai-core/scripts/oss-cad-shim",
  "sv-pathfinder.schematicElaborationMode": "shallow",   // "full" is fine for small tops
  "sv-pathfinder.schematicIncludeDirs": [],              // add `include dirs here if needed
  "sv-pathfinder.schematicShowDanglingNets": false,
  "sv-pathfinder.schematicSpacing": "comfortable"
}
```

## 7. View a schematic

1. Open the **sv-pathfinder** activity-bar view → **Open Design** (or command palette:
   `sv-pathfinder: Open Design`) → select `projects/ai-core/scripts/view/ai-core.f`.
2. Browse the elaborated hierarchy tree.
3. **Right-click a scope → Show Schematic** (e.g. the top, or a sub-instance like a `pe`).
4. In the schematic: step into child scopes, step out to parent, expand instances.

## 8. Verify / troubleshoot

- `read_slang` missing (schematic fails, "No such command: read_slang") → `ossCadSuitePath` wrong,
  wrapper not executable, or the extension bypassed the wrapper. Re-run the §4 sanity check.
- Empty/failed hierarchy → slang-server didn't parse the `.f`; check file paths, include dirs, and
  the **Output panel → "slang-server"** channel.
- Schematic won't render → open the extension's Output/log channel, find the actual `yosys`
  command it ran, and reproduce it in a terminal to see the real error.
- Cross-check elaboration against synthesis: `make syn PROJECT=ai-core TOP_LEVEL=<top>` should
  elaborate the same sources cleanly.

## 9. `sv-pathfinder` settings reference

| Setting | Default | Purpose |
|---|---|---|
| `sv-pathfinder.compiler` | `slang-server` | Navigation backend: `slang-server` or `Surelog` |
| `sv-pathfinder.surelogPath` | `""` | Surelog exe path (only if using Surelog); PATH if empty |
| `sv-pathfinder.ossCadSuitePath` | `""` | Dir containing `bin/yosys` for the schematic; PATH if empty |
| `sv-pathfinder.schematicElaborationMode` | `shallow` | `shallow` (on-demand, cheap) or `full` (one-shot) |
| `sv-pathfinder.schematicIncludeDirs` | `[]` | Extra include dirs for Yosys (`-I`/`-y`) |
| `sv-pathfinder.schematicShowDanglingNets` | `false` | Show unconnected named nets as dashed labels |
| `sv-pathfinder.schematicSpacing` | `comfortable` | Layout density: `compact`/`comfortable`/`spacious` |
| `sv-pathfinder.schematicAccentColor` | `""` | CSS accent color; theme default if empty |
| `sv-pathfinder.valueAnnotationFormat` | `hexadecimal` | Bus value format (waveform only) |
| `sv-pathfinder.sourcePathFrom` / `sourcePathTo` | `""` | Path remapping for jump-to-source |
| `sv-pathfinder.showModulesView` | `true` | Show the Modules view (needs window reload) |

## 10. Caveats

- Extension is **v0.3.0**, published 2026-07-25 — young; expect rough edges.
- The wrapper trick depends on how the extension invokes Yosys; re-verify against its source (§4).
- Two separate toolchains (slang-server for nav, yosys-slang for the schematic) — a failure in one
  does not implicate the other.
