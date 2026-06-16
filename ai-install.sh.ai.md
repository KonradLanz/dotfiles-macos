# ai-install.sh
> Installs a minimal `.ai/` scaffold into a target repository so that repo-local AI context, ignore rules, watch policy, cache, and state can be managed consistently.

## 0. Entry points
- Start at the top for target repo and optional template source handling.
- Main body creates directories and writes default `.ai` files.
- Related files: `.ai/context.md`, `.ai/ignore`, `.ai/watch-policy.json`, `.ai/state.json`.
- Known good command: `bash ai-install.sh ~/git/eudi-nexus`.

## 1. Purpose
This script standardizes the initial `.ai` layout for any repo so bootstrap and checksum tools can work immediately.

## 2. Structure
- Resolve target repo and optional template source.
- Ensure `.ai/` directories exist.
- Copy template content if present.
- Write default context, ignore, watch policy, state, and README files.

## 3. Interfaces
- Writes: `.ai/README.md`, `.ai/context.md`, `.ai/ignore`, `.ai/watch-policy.json`, `.ai/state.json`, plus cache/session/checksum directories.
- Parameters: target repo path, optional template source path.

## 4. Change notes
- Stable: scaffold layout and default file set.
- Likely to change: richer template content, peer metadata, or bootstrap defaults.
