# AI sidecar convention

A lightweight convention for per-file and per-artifact sidecars that help rebuild context quickly without loading full source or binary content.

## Recommendation

This is **not overkill** if kept small and optional. Use sidecars only for high-value files or generated artifacts where summary-first access is useful.

## Goals

- Give an AI one small file to read before opening the real artifact.
- Keep routing information near the file it describes.
- Make binary and generated files readable through markdown summaries.
- Support fast entry points, change tracking, and selective drill-down.

## Naming convention

Preferred sidecar naming:

- `file.ext.ai.md` for a single file, for example `mcp-filelist.sh.ai.md`
- `artifact.pdf.ai.md` for binary/generated artifacts
- `dir/.ai/index.md` for directory-level summaries
- `dir/.ai/files.tsv` for compact machine-readable maps if needed later

This keeps the sidecar colocated with the file and easy to discover.

## Minimal sidecar format

Every `*.ai.md` file should follow this layout:

```markdown
# <filename>
> One-sentence abstract. This is always the first high-signal line.

## 0. Entry points
- Read from line X to Y for the core flow.
- Start at function/script section: <name>
- Related files: <path>, <path>
- Known good commands: <command>

## 1. Purpose
Short explanation of what the file does and when to read it.

## 2. Structure
- Main sections
- Key functions / stages
- Inputs / outputs

## 3. Interfaces
- CLI flags, functions, environment variables, files read/written

## 4. Change notes
- What tends to change
- What is stable
- Which checksums or generated outputs are relevant
```

## Abstract rule

The first non-heading content should always be a one-line abstract in blockquote form:

```markdown
> Builds focused or deep AI bootstrap context for a repo and its neighbours.
```

This matches AI expectations well because it gives a compact summary immediately, before details or examples.

## Section 0 rule

`## 0. Entry points` is a good idea. It should stay short and operational.

Use it for:
- where to start reading,
- the most important function or block,
- one or two grep/from-to anchors,
- related files,
- known working commands.

Do **not** make it a dump of every symbol in the file.

## Good entry-point patterns

For shell scripts, the most useful anchors are usually:
- shebang + option parsing block,
- helper function names,
- dispatch section,
- `case` arms,
- files read/written,
- example commands.

Simple anchor examples:

- `from: option parsing → to: dispatch`
- `grep: '^case .*MODE'`
- `grep: '^_[a-zA-Z0-9]+\(\)'`
- `grep: '^find '`, `grep: '^awk '`, `grep: '^while '`

## Auto-generation guidance

A sidecar can be created from comments plus a few heuristics.
For shell files, extract these in order:
1. top comment block,
2. usage line,
3. named functions,
4. case/dispatch modes,
5. files under `.ai/` that it reads or writes,
6. one short human summary.

If comments are weak, the sidecar should stay short instead of hallucinating detail.

## Scope guidance

Use sidecars for:
- important scripts,
- generated artifacts,
- large configs,
- files that are revisited often,
- files with non-obvious entry points.

Do not create them for every tiny file. That becomes noise.

## Directory-level summaries

For larger repos, add:

- `repo/.ai/index.md` as the repo router,
- `subdir/.ai/index.md` for major subtrees,
- file-level `*.ai.md` only where extra detail helps.

This creates a hierarchy that matches how AI models navigate context best: root summary first, then narrower summaries, then source.

## Match to AI expectations

The best-performing pattern is usually:
1. one-line abstract,
2. small operational entry-points section,
3. compact structure overview,
4. links to related files,
5. only then deep detail.

That is closer to `README`, `AGENTS.md`, and `llms.txt` style routing than to full documentation dumps.

## Recommendation for this repo

Use all three layers:
- `README-ai.md` for the whole system,
- `.ai/index.md` for repo-level routing,
- `*.ai.md` only for key scripts like `ai-bootstrap.sh`, `ai-checksum.sh`, `ai-install.sh`, `mcp-filelist.sh`.

That gives fast routing without sidecar spam.
