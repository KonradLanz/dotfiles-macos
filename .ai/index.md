# dotfiles-macos AI index
> Router for the `.ai` bootstrap helpers, sidecar convention, timeline packets, and the policy that git history must be built in parallel with AI context files.

## 0. Entry points
- Start here for the current AI helper system overview.
- Read `README-ai.md` for workflow, commands, and git-history policy.
- Read `README-ai-sidecars.md` for sidecar conventions.
- Key scripts: `ai-install.sh`, `ai-bootstrap.sh`, `ai-checksum.sh`, `ai-topology.sh`, `mcp-filelist.sh`.
- QNAP storage hygiene: `qnap/fix-symlink-loops.sh` (see Packet H).
- Agent patterns: `.ai/patterns/` (see Packet H).
- Development timeline in this chat: watch cleanup → ignore/context files → `.ai` architecture → install/topology/bootstrap/checksum → sidecars → git-history policy → agent patterns.

## 1. Purpose
This repo now contains a shell-first local AI bootstrap layer for fast repo re-entry, context reuse, topology scanning, change-aware bootstrapping, and commit-aware development flow.

## 2. Core files
- `README-ai.md`: main user-facing design and usage guide
- `README-ai-sidecars.md`: per-file/per-artifact sidecar convention
- `.ai-ARCHITECTURE.md`: phased architecture plan
- `.ai-TODO.md`: roadmap and later extraction note
- `ai-install.sh`: install `.ai/` into a repo
- `ai-bootstrap.sh`: build overview/focused/deep markdown context
- `ai-checksum.sh`: maintain hash manifests for delta detection
- `ai-topology.sh`: zoom-out topology over `~/git`
- `mcp-filelist.sh`: raw file-type summary with ignore-aware filtering
- `qnap/fix-symlink-loops.sh`: POSIX symlink loop detector/resolver for NAS shares

## 3. Agent patterns (NEW — Packet H)
Extracted from operational scripts; applicable to any agent (shell, LLM, cron):
- `.ai/patterns/bounded-iteration.md`: MAX_ITERATIONS + state-file checkpoint/resume
- `.ai/patterns/scope-safeguards.md`: allowlist/denylist for agent action scope
- `.ai/patterns/marker-as-memory.md`: co-located decision records as persistent memory

## 4. Suggested read order
1. `README-ai.md`
2. `.ai-ARCHITECTURE.md`
3. `.ai-TODO.md`
4. `ai-bootstrap.sh.ai.md`
5. `ai-checksum.sh.ai.md`
6. `ai-install.sh.ai.md`
7. `mcp-filelist.sh.ai.md`
8. `.ai/patterns/bounded-iteration.md`
9. `.ai/patterns/scope-safeguards.md`
10. `.ai/patterns/marker-as-memory.md`

## 5. Timeline packets
- Packet A: watch cleanup and decision to avoid permanent watchers.
- Packet B: ignore list and workspace context files.
- Packet C: decision to keep the system in `dotfiles-macos` first.
- Packet D: `.ai` architecture and shell-first phased approach.
- Packet E: install/topology/bootstrap/checksum scripts.
- Packet F: sidecar convention and repo router.
- Packet G: explicit git-history policy for future chats.
- Packet H: QNAP symlink loop resolver + three upstream agent patterns
  (bounded-iteration, scope-safeguards, marker-as-memory).
  Origin: circular Samba symlinks from bootstrap-foundations on QNAP NAS.
  These patterns are protocol/platform-agnostic and apply equally to
  shell scripts, LLM agent loops, and MCP server tool cycles.

## 6. Parallel git policy
- `.ai` files explain routing, intent, and resume state.
- Git commits preserve the ordered execution history.
- Every coherent development packet should end in a checkpoint commit.
- `.ai/index.md` and `.ai/sessions/` should reference the same semantic packets as the commit flow.
