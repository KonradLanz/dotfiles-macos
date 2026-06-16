# ai-checksum.sh
> Tracks repo file changes with SHA256 or CRC32 manifests so generated or binary artifacts only need to be reloaded into context when they actually changed.

## 0. Entry points
- Start at the CLI option parsing block to see `--repo`, `--algo`, `--check`, `--update`.
- Core functions: `_hash_file`, `_scan`.
- Main flow branches at the `if [[ $CHECK -eq 1 ]]` / `elif [[ $UPDATE -eq 1 ]]` section.
- Related files: `.ai/ignore`, `.ai/checksums/*.tsv`.
- Known good command: `bash ai-checksum.sh --repo ~/git/dotfiles-macos --update`.

## 1. Purpose
This script replaces always-on watching for many use cases by maintaining explicit checksum manifests and reporting only changed, new, or deleted files.

## 2. Structure
- Parameter parsing and manifest path selection.
- Hashing abstraction for `sha256` and `crc32`.
- Ignore-aware repo scan.
- Two modes: update manifest or check for delta against a stored manifest.

## 3. Interfaces
- Reads: `.ai/ignore`.
- Writes: `.ai/checksums/sha256.tsv` or `.ai/checksums/crc32.tsv`.
- Parameters: `--repo`, `--algo`, `--check`, `--update`.

## 4. Change notes
- Stable: manifest TSV model and ignore-aware scan.
- Likely to change: performance tuning, ignore matching, and support for richer manifests or per-subtree scopes.
