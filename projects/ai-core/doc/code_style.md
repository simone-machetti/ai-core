# Code style

Coding rules and conventions for the **ai-core** project — RTL and its docs. This is a living
document: add to it as new conventions are agreed.

## SystemVerilog

### File header

Every `.sv` file begins with the author header block, describing the module and listing its
parameters:

```
// -----------------------------------------------------------------------------
// Author: Simone Machetti
//
// Description:
//   <what the module does>
//
// Parameters:
//   PARAM - <meaning>
// -----------------------------------------------------------------------------
```

The author is always **Simone Machetti**, regardless of original authorship.

### Comments

**No inline comments** in the module body — the header is the only documentation. The single
exception is **Verilator lint pragmas** (`/* verilator lint_off <WARN> */` … `/* verilator lint_on
<WARN> */`), which are allowed to suppress legitimate, config-dependent warnings (e.g. an input that
is genuinely unused in some parameterization).

### Formatting

- Indent with **4 spaces**; never tab characters.
- `` `timescale 1 ns/1 ps `` after the header.
- Align port declarations (the bit-range column) and the `=` in the parameter list.

### Signal naming

- **lowercase**, with an `_i` / `_o` **direction suffix**; `_n` for active-low
  (e.g. `clk_i`, `rst_ni`, `d_i`, `q_o`, `is_signed_i`).
- Use these even though the diagrams and spec label signals in UPPERCASE (`PE_IN_A`, `MODE`) — the
  uppercase names are just drawing notation.

### Instance naming

- Name every instance `<module_name>_i` (e.g. `ext_n` → `ext_n_i`, `fa` → `fa_i`, `cpr_w_n` → `cpr_w_n_i`).
- For **multiple equal instances at the same scope**, insert a disambiguator: `<module_name>_<x>_i`
  (e.g. `fa_0_i`, `fa_1_i`). Inside a `generate` loop the loop index already disambiguates the
  hierarchical path, so the base `<module_name>_i` is fine.
- In instantiation port / parameter maps, write arithmetic expressions **tight** — no spaces around
  operators: `.SHIFT(2*j)`, `.IN_SIZE(2*PP_SIZE)`, `.WIDTH(CPR2_WIDTH+2*j)`. (Elsewhere — `localparam`
  and `assign` expressions — keep the usual spaces around operators.)

### Parameterization

- Every module is **general and parameterized** (widths, sizes, counts, ops) so one source is reused
  across instances and projects. Merge variants that differ only by a parameter into one module.
- **Fixed dimensions are compile-time `parameter int`.** Express *growth* as a parameter and
  **derive** the output width in a `localparam` — do **not** take an absolute output width parameter:
  - `OUT_WIDTH = IN_WIDTH + EXT`  (`cpr_c_n` / `cpr_w_n`, `ext_n`)
  - `OUT_WIDTH = WIDTH + SHIFT`   (`shift_n`)
  - `OUT_WIDTH = WIDTH + 1`       (`add_n`)
- Give a growth parameter a sensible default where one exists (e.g. the compressors' `EXT = $clog2(IN_SIZE)`).
- **Behavior that changes with the operating mode is a runtime input signal, not a parameter.** In
  particular **signedness is runtime** where the *same instance* must switch with the mode: use an
  `is_signed_i` input (per-operand — `is_signed_a_i` / `is_signed_b_i` — where A and B differ) on
  `shift_n`, `ext_n`, `add_n`, and the DP.
  - **Exception — signedness fixed by structure is a compile-time `IS_SIGNED` parameter.** The
    compressors (`cpr_c_n` / `cpr_w_n`) take `parameter bit IS_SIGNED`, not a runtime signal: a
    compressor's input signedness is set by where it sits in the datapath and never switches with the
    mode. Rule of thumb: runtime `is_signed_i` only when one instance genuinely sees both signed and
    unsigned data across modes; otherwise a parameter.
- Declare derived values as `localparam` inside the parameter list, after the `parameter`s.

### Lint

- Every module elaborates clean under `verilator --lint-only -sv -Wall`.
- Suppress only legitimate, unavoidable, config-dependent warnings, with scoped lint pragmas.

### Reuse from ai-core-legacy

- Reusing a proven cell from `ai-core-legacy` is allowed, **approved per component**. Copy the file
  into this project's `rtl/` **verbatim** (keeping its header and pragmas) — e.g. `fa.sv`.

## Module docs (`.md`)

- A module's design doc lives in the project **wiki** at `wiki/modules/<module>.md` (OKF v0.1), **not**
  next to the `.sv`. Add/refresh it with the `update-wiki` skill.
- Each page: YAML frontmatter (`type: module`, `title`, `description`, `resource: rtl/<module>.sv`,
  `tags`, `timestamp`), a 1–3 sentence summary, `# Schema` (parameters + ports/interface tables),
  `# Examples` (a fenced ```systemverilog snippet, plus how a `tb/` exercises it if applicable), and a
  `Source:` link back to the `.sv`.
- **Cross-link** related pages with relative markdown links (a composite links the modules it
  instantiates; a module links the compressor/concept it uses). This is OKF-conformant and graphs in
  Obsidian — the opposite of the old self-contained rtl/*.md rule it replaces.

## Testbenches

All self-checking testbenches share **one structure** — file `tb/tb_<dut>.sv`, top module `tb_<dut>`:

- Header, then `/* verilator lint_off UNUSEDSIGNAL */`.
- `module tb_<dut> #(<DUT params…>, parameter int NUM_RAND = 2000);`
- Derived `localparam`s, the DUT I/O signals, and the DUT instance named `<dut>_i`.
- Three tasks:
  - `check(input bit sgn)` — set the control(s), `#1`, compute a golden value, read the DUT outputs,
    and on mismatch `$dumpoff` + `$error(...)` + `$fatal`.
  - `rand_vec` — randomize all inputs with `$urandom`.
  - `set_vec(...)` — set fixed inputs (used for corner cases).
- **Named `localparam` stimulus constants** for the corner cases — `ZERO`, `ALL_ONES`, `MAX_POS`,
  `MIN_NEG` (per operand, e.g. `A_MAX_POS`/`B_MAX_POS` when there are two) — never inline bit
  constructions in the `set_vec` calls.
- `initial` block, in order: banner `$display`; `$dumpfile("activity.vcd")` + `$dumpvars(0,
  tb_<dut>.<dut>_i)`; a `NUM_RAND` loop of `rand_vec; check(1'b0); check(1'b1);`; corner cases
  (`set_vec(<named constants>); check(1'b0); check(1'b1);`, signed and unsigned each); `$dumpoff`;
  `$display("<dut>: all %0d ... PASSED!", NUM_RAND)`; `$finish`.

Only the DUT-specific parts differ: the port list, the golden model inside `check`, and the
`set_vec`/corner values.

## Markdown

- All markdown tables are **pipe-aligned** — cells padded with spaces so the `|` line up in the
  source, with per-column alignment (`:--`, `--:`) preserved.
