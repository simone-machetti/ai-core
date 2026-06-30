---
name: update-wiki
description: Update a project's OKF design-doc wiki under projects/<project>/wiki/ after design progress — ingest new or changed rtl/tb/doc into concept pages, refresh index.md and log.md, and lint for conformance. Use when the user wants to sync/update the wiki, document recent design changes, or capture new/modified RTL, testbenches, or docs into the wiki.
---

# Update the project wiki

Bring a project's design-documentation **wiki** up to date with its source folders. The wiki is an **OKF v0.1** bundle (a directory of markdown files with YAML frontmatter) that the LLM maintains from the project's own `rtl/`, `tb/`, and `doc/` sources. This skill performs one *ingest + lint* pass: read what changed, write/refresh the affected concept pages, update the catalog and log, and check conformance.

Background: OKF (Open Knowledge Format) defines the file format; the operating model (ingest / query / lint, a compounding wiki) follows Karpathy's LLM-wiki pattern. This skill is the *ingest + lint* half.

## 1. Resolve the target project and wiki

- The project name comes from the invocation (e.g. `/update-wiki ai-core`). If none is given, default to `ai-core`.
- The wiki bundle is `projects/<project>/wiki/`. If it does not exist, tell the user and offer to scaffold it (`index.md` + `log.md` + the category folders) first — do not invent a different location.
- The source material is the sibling folders `projects/<project>/{rtl,tb,doc}`. Treat these as **read-only** inputs; never edit them from this skill.

Below, `<wiki>` = `projects/<project>/wiki` and `<src>` = `projects/<project>`.

## 2. Conventions (binding — every page must follow these)

Format and layout:
- **Reserved files:** `index.md` (catalog) and `log.md` (history) — see §5, §6. Only the **root** `index.md` carries frontmatter, and only `okf_version: "0.1"`.
- **Concept page = one markdown file** with a YAML frontmatter block. **Required:** non-empty `type`. **Recommended:** `title`, `description` (one sentence), `resource` (path to the source artifact, project-root-relative and uniform across pages, e.g. `rtl/adder_n.sv`), `tags` (YAML list), `timestamp` (ISO-8601 date — use today's via `date +%F`).
- **`type` vocabulary (8):** `module`, `architecture`, `concept`, `decision`, `experiment`, `reference`, `term`, `schema`.
- **Folder per type:** `architecture/`, `modules/`, `concepts/`, `decisions/`, `experiments/`, `references/`. `term` pages go flat in `<wiki>/` (or a `glossary/` folder if one exists); `schema` is the single `conventions.md` file.
- **Filenames:** kebab-case, no spaces; mirror the source basename where natural (`rtl/adder_n.sv` → `modules/adder_n.md`).

Body and links:
- Favor structural markdown: a short prose summary, then tables/lists. Use the conventional headings where useful: `# Schema` (parameters/ports/interface), `# Examples` (usage, key snippet), `# Citations` (external sources, numbered `[1] [Title](url)`).
- **Quote RTL inline** in fenced code blocks (```systemverilog) rather than relying on the source file rendering — Obsidian does not preview `.sv` files inline.
- **Cross-links and the body source link use relative markdown links.** From `<wiki>/modules/adder_n.md`, link the source as `[adder_n.sv](../../rtl/adder_n.sv)` and a sibling page as `[cpr_n_2](./cpr_n_2.md)` (or `../concepts/...`). Relative links stay clickable, graphed, and auto-updated on move in Obsidian. Do **not** use absolute `/path` links. (The `resource` frontmatter stays project-root-relative as a stable identifier; the clickable link in the body is page-relative.)
- Keep pages human-readable and concise — the reader is the user, not only a machine.

## 3. Determine what changed

- Inspect git, scoped to the sources: `git status --porcelain -- <src>/rtl <src>/tb <src>/doc` and `git diff --name-only -- <src>/rtl <src>/tb <src>/doc`. Also consider files newer than the latest `log.md` date.
- Ask the user to confirm or narrow the set (e.g. "I just added the Winograd top-level") — they know what is design-complete vs. work-in-progress. **Only document what is real and ready**; do not create pages for unbuilt or placeholder parts.
- Produce a short work-list: each source to ingest/refresh and the page it maps to. Confirm with the user before writing.

## 4. Write or refresh the concept pages

For each item in the work-list:
1. Pick `type`, target folder, and kebab-case filename.
2. Read the source file(s), then write/refresh the page:
   - Frontmatter per §2 (set/refresh `timestamp` to today; keep `resource` pointing at the source).
   - A 1–3 sentence summary of what it is and its role in the design.
   - `# Schema`: parameters, ports, and key interface as a table.
   - `# Examples`: the essential snippet (fenced ```systemverilog), and how a `tb/` testbench exercises it if applicable.
   - A source line: `Source: [<file>](<relative path>)`.
3. **Cross-reference:** link related pages (a `top_*` architecture page links each module it instantiates; a module links the concept it implements). Add reciprocal links where they aid navigation.

## 5. Update `index.md`

- `index.md` is the catalog: grouped `## <Section>` blocks of `* [Title](relative/path.md) - one-line description`.
- Add or refresh each page's entry under the section matching its `type`; replace the `_None yet._` placeholder when a section gets its first page.

## 6. Append to `log.md`

- Newest first. Under a `## YYYY-MM-DD` heading for today (create it at the top if absent), add one line per change: `- **[Creation]**: <page> — <short note>` or `- **[Update]**: <page> — <what changed>`, linking the page.

## 7. Lint

Run a conformance + health check and report findings:
- Every non-reserved `.md` under `<wiki>/` has a parseable frontmatter block with a **non-empty `type`**.
- `index.md` / `log.md` are well-formed (root index declares `okf_version`; log is date-grouped, newest first).
- Relative links resolve to existing files (broken links are tolerated by OKF, but list them anyway).
- **Index coverage:** every concept page appears in `index.md`; no index entry points to a missing page.
- **Orphans / stale:** flag pages with no inbound or outbound links, and pages whose `resource` source has changed in git since the page's `timestamp` (candidates for refresh).

## 8. Report

Summarize: pages created/updated, index/log changes, and lint results (with any issues to fix). Do **not** commit anything unless the user asks.
