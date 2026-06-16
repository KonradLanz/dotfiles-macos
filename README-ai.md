# AI bootstrap layer (`dotfiles-macos`)

A lightweight meta-context network for fast, efficient AI chat re-entry across multiple repositories.
The design goal is a local `.ai/` layer per repo that serves as a **cache, context anchor, navigation node, and git-aware progress tracker** in a workspace graph.

## Scripts

| Script | Purpose |
|---|---|
| `ai-install.sh` | Install `.ai/` scaffold into a repo |
| `ai-bootstrap.sh` | Generate structured Markdown context (overview, focused, deep) |
| `ai-checksum.sh` | Generate and verify SHA256/CRC32 manifests for change detection |
| `ai-topology.sh` | Scan a root for repos with `.ai/` layers |
| `mcp-filelist.sh` | Raw file-type summary with ignore filtering |

## Quick start

```bash
# 1. Install .ai layer in a repo
bash ai-install.sh /Users/koni/git/eudi-nexus

# 2. Zoom out from ~/git (overview of all .ai repos)
bash ai-bootstrap.sh --mode overview --root ~/git --depth 2

# 3. Focused context for one repo
bash ai-bootstrap.sh --mode focused --repo ~/git/eudi-nexus

# 4. Deep context with peers and delta since last session
bash ai-bootstrap.sh --mode deep --repo ~/git/eudi-nexus --peers --since-last

# 5. Neighbour query: peer repos up to depth 3 around a repo
bash ai-bootstrap.sh --mode focused --repo ~/git/eudi-nexus --peers --depth 3

# 6. Initial checksum manifest
bash ai-checksum.sh --repo ~/git/eudi-nexus --update

# 7. What changed since the last manifest?
bash ai-checksum.sh --repo ~/git/eudi-nexus --check
```

## Git history policy

Every chat that changes files should also maintain a parallel git history.
The `.ai` layer is good for context routing, but it does not replace commits as the time-ordered source of truth.

Recommended policy:
- create a small checkpoint commit after each coherent development packet,
- keep commit scope aligned with the semantic packet described in `.ai/index.md` or `.ai/sessions/`,
- use `.ai` files to explain *why* and git commits to record *what changed when*,
- prefer several small commits over one large end-of-chat commit,
- if work is exploratory, use explicit WIP checkpoints and later squash if needed.

Recommended packet rhythm:
1. plan or architecture note,
2. file creation/editing,
3. sidecars or session notes,
4. checkpoint commit,
5. continue with next packet.

## `.ai/` structure

```text
.ai/
  README.md          # short description
  context.md         # human-maintained repo summary and entry hints
  index.md           # repo router and timeline packets
  ignore             # repo-local ignore rules (appended to built-in defaults)
  watch-policy.json  # which file types and paths are worth watching
  state.json         # last bootstrap, last focus, peer list, visited nodes
  sessions/          # per-topic notes for parallel chats
  checksums/         # sha256.tsv / crc32.tsv manifests
  manifests/         # larger derived summaries
  cache/             # temporary derived outputs, always ignorable
```

## Modes and depth control

| Mode | Contains |
|---|---|
| `overview` | Workspace topology, all repos with `.ai/` at given depth, symlink edges |
| `focused` | context.md, state, priority files, file-type summary, optional peers |
| `deep` | All of focused + delta since last session, checksums, session history, peers |

Switching detail levels in a chat:

```bash
# Zoom out
bash ai-bootstrap.sh --mode overview --root ~/git --depth 3

# Zoom into a specific repo
bash ai-bootstrap.sh --mode focused --repo ~/git/contributions-analyser

# Navigate to a peer (neighbour query)
bash ai-bootstrap.sh --mode focused --repo ~/git/contributions-analyser --peers --depth 2
```

## Acyclic graph navigation

When traversing symlinks or peer repos, the bootstrap script keeps a visited set of canonical paths.
A path is only entered once per invocation. This prevents cycles in symlink graphs, cross-linked
repos, or workspace setups with shared peers.

- Cycle detection is on by default.
- Pass `--no-cycle-check` only for debugging flat structures.
- Symlinks are reported as graph edges with `→ symlink: target` notation.

## Checksum-based change detection

`ai-checksum.sh` maintains a TSV manifest of file hashes, filtered by `.ai/ignore`.
Only files whose hash changed since the last `--update` run appear in `--check` output.
This replaces permanent file watchers with on-demand, cache-aware delta detection.

For binary or generated artefacts (PDFs, compiled outputs, JSON pipelines):
- Run `--update` after a pipeline produces new outputs.
- Run `--check` at chat start to know what changed without re-loading everything.
- Use CRC32 (`--algo crc32`) for faster scans on large binary file sets.

## Chat bootstrap prompt (copy into new chat)

```text
Build Repo Structure Context
- Establish repo context with .ai router and sidecars.
- Build and maintain git history in parallel with changes.
- Work in small semantic packets and checkpoint them in git.
- Use overview/focused/deep as needed; prefer focused by default.
- Record important decisions in .ai/index.md or .ai/sessions/.
```

Then paste the stdout of one of:

```bash
bash ~/git/dotfiles-macos/ai-bootstrap.sh --mode overview --root ~/git
bash ~/git/dotfiles-macos/ai-bootstrap.sh --mode focused --repo ~/git/YOUR-REPO
bash ~/git/dotfiles-macos/ai-bootstrap.sh --mode deep    --repo ~/git/YOUR-REPO --since-last --peers
```

## Design notes

- **Shell-first**: no Python, no extra dependencies, fast startup. See `README-shell-performance.md`.
- **Cache-aware**: checksums avoid reloading unchanged artefacts into context.
- **Acyclic traversal**: explicit visited set prevents infinite loops in symlinked workspaces.
- **Git-aware**: `.ai` provides routing and summaries, while git provides the ordered execution history.
- **Stateless protocol**: each script invocation produces Markdown for the AI context window; no persistent daemon or background process required.
- **Phased roadmap**: start with shell, add Python utilities for complex state if needed, promote to a proper Python MCP server only when repo-scale tool calls are necessary. See `.ai-ARCHITECTURE.md` for the phased plan and `.ai-TODO.md` for next steps.

## Extraction note

Keep all of this in `dotfiles-macos` until the workflow is stable across several repos.
Extract to generic `dotfiles` only when macOS-specific assumptions are removed and
a cross-platform interface is clear. Tracked in `.ai-TODO.md`.
