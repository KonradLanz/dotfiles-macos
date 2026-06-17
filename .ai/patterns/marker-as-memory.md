# Pattern: Marker File as Persistent Decision Record

## Problem
An automated agent takes an action (removes a file, fixes a symlink,
patches a config). Later — in a different context, session, or run —
neither the agent nor a human can tell what happened, why, or how to
undo it.

## Solution

Every destructive or mutating action leaves a **human-readable marker file**
next to the affected artefact. The marker is:
- Self-describing (what was here, what happened, when, why)
- Actionable (how to restore if wrong)
- Idempotency guard (presence prevents re-action)
- Persistent memory across agent contexts

## Implementation (from qnap/fix-symlink-loops.sh)

```sh
MARKER_SUFFIX=".removed.symlink.txt"

write_marker() {
  link_path="$1"
  target=$(readlink "$link_path")
  marker="${link_path}${MARKER_SUFFIX}"
  cat > "$marker" << EOF
REMOVED SYMLINK — $(date '+%Y-%m-%dT%H:%M:%S')
Original symlink : $link_path
Pointed to       : $target
Reason           : circular loop causing infinite SMB directory tree
Removed by       : fix-symlink-loops.sh
Restore with     : ln -s "$target" "$link_path" && rm "$marker"
EOF
}

# Skip if already resolved (idempotency)
[ -f "${link}${MARKER_SUFFIX}" ] && continue
```

## Mapping: Script ↔ .ai folder ↔ LLM Agent

| Script concept          | .ai folder equivalent         | LLM agent concept              |
|-------------------------|-------------------------------|--------------------------------|
| `.removed.symlink.txt`  | `.ai/decisions/YYYY-MM-DD.md` | Agent scratchpad / audit log   |
| Marker content          | ADR (Architecture Decision)   | Tool call reasoning record     |
| Idempotency check       | Already-seen set in memory    | Deduplication in context       |
| Restore instructions    | Rollback notes in ADR         | Undo plan in agent memory      |
| `write_marker()` call   | Commit message + sidecar      | Memory write before action     |

## Naming conventions

| Suffix pattern              | Meaning                              |
|-----------------------------|--------------------------------------|
| `<name>.removed.symlink.txt`| Symlink was a loop, removed          |
| `<name>.ai.md`              | AI sidecar for a script/file         |
| `<name>.decision.md`        | Architecture/automation decision     |
| `<name>.bak`                | Generic backup before mutation       |

## Why marker > log-only

A log file requires the reader to correlate log entries to filesystem
locations. A marker file is **co-located** with the change — the reader
finds it exactly where they would look when confused about what something
is. This is the same reason `.ai.md` sidecars live next to their scripts.

## References
- `qnap/fix-symlink-loops.sh` — origin of this pattern
- `README-ai-sidecars.md` — the broader sidecar convention
- `.ai/patterns/bounded-iteration.md`
- `.ai/patterns/scope-safeguards.md`
