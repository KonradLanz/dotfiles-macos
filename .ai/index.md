# dotfiles-macos AI index
> Router for the `.ai` bootstrap helpers, sidecar convention, timeline packets, and the policy that git history must be built in parallel with AI context files.

## 0. Entry points
- Start here for the current AI helper system overview.
- Read `README-ai.md` for workflow, commands, and git-history policy.
- Read `README-ai-sidecars.md` for sidecar conventions.
- Key scripts: `ai-install.sh`, `ai-bootstrap.sh`, `ai-checksum.sh`, `ai-topology.sh`, `mcp-filelist.sh`.
- Development timeline in this chat: watch cleanup → ignore/context files → `.ai` architecture → install/topology/bootstrap/checksum → sidecars → git-history policy.

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

## 3. Suggested read order
1. `README-ai.md`
2. `.ai-ARCHITECTURE.md`
3. `.ai-TODO.md`
4. `ai-bootstrap.sh.ai.md`
5. `ai-checksum.sh.ai.md`
6. `ai-install.sh.ai.md`
7. `mcp-filelist.sh.ai.md`

## 4. Timeline packets
- Packet A: watch cleanup and decision to avoid permanent watchers.
- Packet B: ignore list and workspace context files.
- Packet C: decision to keep the system in `dotfiles-macos` first.
- Packet D: `.ai` architecture and shell-first phased approach.
- Packet E: install/topology/bootstrap/checksum scripts.
- Packet F: sidecar convention and repo router.
- Packet G: explicit git-history policy for future chats.

## 5. Parallel git policy
- `.ai` files explain routing, intent, and resume state.
- Git commits preserve the ordered execution history.
- Every coherent development packet should end in a checkpoint commit.
- `.ai/index.md` and `.ai/sessions/` should reference the same semantic packets as the commit flow.
