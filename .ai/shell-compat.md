# Shell Compatibility Matrix

> Lessons captured from real cross-platform scripting across
> macOS (zsh/bash), QNAP QTS (ash/BusyBox), Alpine (ash), Ubuntu (bash/dash).
> Last updated: 2026-06-17

## Shell Landscape

| Shell | Where | POSIX? | Notes |
|---|---|---|---|
| `zsh` | macOS default (10.15+), Kali | superset | `#!/bin/zsh` — arrays, associative arrays, `${(f)...}` |
| `bash` | Linux default, macOS (Homebrew) | superset | `#!/bin/bash` — `[[`, arrays, `<<<`, process substitution |
| `dash` | Ubuntu `/bin/sh`, Debian | strict | Fast. No arrays. `#!/bin/sh` on Ubuntu runs dash |
| `ash` | Alpine, BusyBox, QNAP QTS | near-POSIX | BusyBox multi-call binary. Missing many GNU extensions |
| `sh` | Symlink — points to dash/ash/bash | POSIX only | Never assume which shell. Write to lowest common denominator |

## QNAP QTS Specifics

```
BusyBox v1.24.1 (2026-03-27) — ash shell
/bin/sh -> busybox ash
```

- **No `bash`** unless Entware installs it to `/opt/bin/bash`
- **No `sort -h`** — `-h` flag not in BusyBox v1.24 `sort`; use `sort -rn` with `-sk`
- **`df -k` returns 0 on NFS mounts** — BusyBox cannot `statvfs()` NFS
- **`2>/dev/null` after `[`** does not suppress the error — the error fires before redirection
- **`crontab -l`** and `cat /etc/config/crontab` produce identical output — same file
- **`/etc/config/crontab`** persists across reboots; `/etc/crontab` does not
- **`/root`** is on a 400MB tmpfs/flash partition — never clone repos there directly
- **`/opt`** is Entware mount — survives reboots only if Entware autostart is configured

## Portability Rules (POSIX sh / BusyBox safe)

### Integer guard — never compare potentially empty variable

```sh
# BAD — crashes with 'integer expression expected' if VAR is empty
[ "$VAR" -lt 100 ]

# GOOD — default to 0 if empty
[ "${VAR:-0}" -lt 100 ]

# ALSO GOOD — skip guard if empty
[ -n "$VAR" ] && [ "$VAR" -lt 100 ] && echo "small"
```

### Sort — no -h in BusyBox

```sh
# BAD on QNAP/Alpine
du -sh /path | sort -h

# GOOD everywhere
du -sk /path | sort -rn    # outputs KB, sorts numerically
```

### df on NFS mounts (BusyBox)

```sh
# BAD — returns 0 on NFS under BusyBox
df -k /share/CE_CACHEDEV4_DATA/homes/... | awk 'NR==2{print $4}'

# GOOD — resolve mountpoint via /proc/mounts first
df_free_kb() {
  mp=$(awk -v p="$1" '
    BEGIN{best=""}
    {if(index(p,$2)==1 && length($2)>length(best)) best=$2}
    END{print best}
  ' /proc/mounts)
  [ -z "$mp" ] && mp="$1"
  df -k "$mp" | awk 'NR==2{print $4}'
}

# Always guard against empty/zero result
FREE=$(df_free_kb /path)
[ "${FREE:-0}" -gt 0 ] && echo "${FREE}KB free" || echo "unknown (NFS)"
```

### du depth — BusyBox has --max-depth but not always -d

```sh
# Most portable
du --max-depth=1 -k /path 2>/dev/null || du -d1 -k /path
```

### Command existence check

```sh
# GOOD — POSIX, works everywhere
if command -v vim >/dev/null 2>&1; then
  vim "$file"
fi

# BAD — 'which' not always available or may print to stdout
if which vim; then ...
```

### Shebang strategy

```sh
#!/bin/sh            # Scripts that must run on QNAP/Alpine/BusyBox/dash
#!/bin/bash          # Only when bash features are required (arrays etc.)
#!/usr/bin/env bash  # Portable bash — finds Homebrew bash on macOS
#!/usr/bin/env zsh   # macOS-only scripts
```

> For performance benchmarks of these choices see
> `README-shell-performance.md` in this repo.

## Feature Matrix

| Feature | POSIX sh | dash | ash/BusyBox | bash | zsh |
|---|---|---|---|---|---|
| Arrays `arr=()` | ❌ | ❌ | ❌ | ✅ | ✅ |
| `[[` test | ❌ | ❌ | ❌ | ✅ | ✅ |
| `<<<` herestring | ❌ | ❌ | ❌ | ✅ | ✅ |
| `${var:-default}` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `$(cmd)` subshell | ✅ | ✅ | ✅ | ✅ | ✅ |
| `local` in functions | ❓ | ✅ | ✅ | ✅ | ✅ |
| `sort -h` | ❌ | ❌ | ❌ | dep. | dep. |
| `du -d1` | ❌ | dep. | ✅ | ✅ | ✅ |
| `readlink -f` | ❌ | ❌ | ✅ | ✅ | ❌ (use `realpath`) |
| `command -v` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `df -h` human | ❌ | dep. | ✅* | ✅ | ✅ |
| `df` on NFS | ❓ | ❓ | ❌** | ✅ | ✅ |
| Process substitution `<()` | ❌ | ❌ | ❌ | ✅ | ✅ |

`*` df -h works but NFS returns 0 for size  
`**` BusyBox df cannot statvfs NFS mounts

## Cross-Reference — POSIX-aware scripts across this ecosystem

### Canonical specs
- [`qnap-dotfiles/commonrc-spec.md`](../qnap-dotfiles/commonrc-spec.md) —
  **the canonical `.commonrc` spec**: POSIX-compatible shared rc file sourced
  by bash, zsh, ash. Covers `$ENV`, POSIX compliance testing, fish caveat.
- [`qnap-dotfiles/.profile`](../qnap-dotfiles/.profile) —
  POSIX login shell init (sourced by sh, dash, ash, bash --login)
- [`README-shell-performance.md`](../README-shell-performance.md) —
  benchmark data: dash fastest for POSIX scripts, zsh up to 4× faster than bash
  in some test cases, recommendation matrix per use case

### Library / reusable POSIX modules
- [`bootstrap-foundation/lib/`](../bootstrap-foundation/lib/) —
  `detect-os.sh`, `detect-hardware.sh`, `secret-backends.sh`, `clone-repos.sh`
  all written to `sh (POSIX)` — no bashisms
- [`bootstrap-foundation/scripts/clone-all.sh`](../bootstrap-foundation/scripts/clone-all.sh) —
  NFS df workaround in production (BusyBox-safe)
- [`bootstrap-foundation/scripts/crontab-dedup.sh`](../bootstrap-foundation/scripts/crontab-dedup.sh) —
  POSIX, auto-detects `/etc/config/crontab` (QNAP) vs `/etc/crontab` (Linux)

### Scripts explicitly targeting BusyBox/Alpine/QNAP
- [`git-history-tools/git-history-clean.sh`](../git-history-tools/git-history-clean.sh) —
  `# POSIX sh - runs on: macOS, Linux, Alpine (WSL2), QNAP BusyBox/Entware`
- [`qnap/fix-symlink-loops.sh`](../qnap/fix-symlink-loops.sh) —
  POSIX symlink loop detector/resolver for NAS Samba/NFS shares
- [`local-ai-stack/catwalk/link-ollama-models.sh`](../local-ai-stack/catwalk/link-ollama-models.sh) —
  pure POSIX, no external deps beyond grep/sed/find
- [`local-ai-stack/catwalk/import-ollama-models-2-lm-studio.sh`](../local-ai-stack/catwalk/import-ollama-models-2-lm-studio.sh) —
  pure POSIX, no jq
- [`paperless-ngx-qnap-bootstrap`](../paperless-ngx-qnap-bootstrap/) —
  only POSIX shell + Docker required

### Test scripts written to POSIX
- [`hotkey-asr-assistant/tests/smoke_whisper.sh`](../hotkey-asr-assistant/tests/smoke_whisper.sh)
- [`hotkey-asr-assistant/tests/smoke_overlay.sh`](../hotkey-asr-assistant/tests/smoke_overlay.sh)
- [`eudi-nexus/test/`](../eudi-nexus/test/) — POSIX shell test suite

### Storage & infrastructure
- [`qnap-storage-advisor/docs/storage-layout.md`](../qnap-storage-advisor/docs/storage-layout.md) —
  QNAP volume topology, /root flash limit, git symlink placement
- [`qnap-storage-advisor/docs/root-flash-overflow.md`](../qnap-storage-advisor/docs/root-flash-overflow.md) —
  incident record: entware-packages 57MB filled /root flash
