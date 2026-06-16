# ai-bootstrap.sh
> Builds overview, focused, or deep markdown context for a repo or workspace, including peers, state, file-type summaries, and optional delta sections.

## 0. Entry points
- Start at the option parsing block near the top for supported modes and parameters.
- Main dispatch is the final `case "$MODE" in` section.
- Core functions to inspect first: `_overview`, `_focused`, `_deep`, `_peer_repos`, `_delta_since_last`, `_print_filetype_summary`.
- Related files: `.ai/context.md`, `.ai/state.json`, `.ai/ignore`, `.ai/checksums/`.
- Known good command: `bash ai-bootstrap.sh --mode focused --repo ~/git/dotfiles-macos --peers --depth 2`.

## 1. Purpose
This script is the main chat bootstrap generator. It emits structured markdown designed to be pasted into a new AI chat to rebuild context efficiently.

## 2. Structure
- CLI parameter parsing for mode, root, repo, depth, peer traversal, and delta controls.
- Shared helper functions for formatting, canonical paths, cycle checks, file summaries, priority files, and delta reporting.
- Three mode handlers: overview, focused, deep.
- Final mode dispatch.

## 3. Interfaces
- Reads: `.ai/context.md`, `.ai/state.json`, `.ai/ignore`, `.ai/checksums/`, `.ai/sessions/`.
- Outputs: markdown to stdout.
- Parameters: `--mode`, `--root`, `--repo`, `--depth`, `--peers`, `--since-last`, `--no-cycle-check`.

## 4. Change notes
- Stable: mode model (`overview`, `focused`, `deep`) and markdown-first stdout design.
- Likely to change: peer traversal, delta logic, file-type summary heuristics, cycle detection details.
