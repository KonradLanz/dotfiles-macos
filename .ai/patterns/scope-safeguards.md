# Pattern: Scope Safeguards (Allowlist / Denylist)

## Problem
An agent or script with write/delete/modify capability must never operate
on paths, APIs, or resources that are outside its declared scope — especially
system paths that may contain intentional structures that look like anomalies.

## Solution

Declare explicit **denied prefixes** (denylist) and derive allowed scope
from configuration sources (e.g. `smb.conf`, `exports`, a YAML file).
Check both before acting on any target.

## Shell implementation (from qnap/fix-symlink-loops.sh)

```sh
# Denylist — hardcoded, never configurable by end-user
SYSTEM_EXCLUDES="/bin /sbin /usr /lib /proc /sys /dev /etc"

is_system_path() {
  for excl in $SYSTEM_EXCLUDES; do
    case "$1" in "$excl"|"$excl/"*) return 0 ;; esac
  done
  return 1
}

# Allowlist — derived from configuration (dynamic)
collect_export_roots()  # reads smb.conf + /etc/exports
```

## Agent scope config template

```yaml
# .ai/config/agent-scope.yaml
allowed_roots:
  - /share/homes
  - /share/Public
  - /share/Multimedia
denied_prefixes:
  - /bin
  - /usr
  - /etc
  - /proc
  - /sys
  - /dev
  - /share/.qpkg
max_iterations_per_run: 200
state_file: /tmp/agent.state
dry_run_default: true
```

## Layers of safeguard (defence in depth)

1. **Scope derivation** — only act on what is explicitly exported/configured
2. **Denylist** — hardcoded system paths, never overridable
3. **Dry-run default** — destructive flag must be explicit (`--fix`)
4. **Idempotency** — marker/seen-set prevents double action
5. **Device boundary** — `find -xdev` prevents crossing mount points

## Mapping: Script ↔ LLM Agent

| Script concept       | LLM agent concept                           |
|----------------------|---------------------------------------------|
| `SYSTEM_EXCLUDES`    | Tool call restrictions / capability limits  |
| `collect_export_roots` | MCP server scope / allowed tool targets   |
| `--fix` explicit flag | Human-in-the-loop approval step           |
| `find -xdev`         | Sandbox boundary / container isolation      |
| Dry-run default      | Read-only mode before write confirmation    |

## References
- `qnap/fix-symlink-loops.sh` — origin of this pattern
- `.ai/patterns/bounded-iteration.md` — how many iterations are allowed
- `.ai/patterns/marker-as-memory.md` — what to record when acting
