#!/bin/sh
# fix-symlink-loops.sh — QNAP/POSIX symlink loop detector & resolver
# Scope: only paths exported via Samba (/etc/samba/smb.conf) or NFS (/etc/exports)
# Safe: read-only by default; use --fix to remove loops
# Repo: dotfiles-macos/qnap/
# Sidecar: fix-symlink-loops.sh.ai.md
#
# AGENT LOOP GUARD PATTERN:
#   MAX_ITERATIONS controls how many symlinks are processed per run.
#   This mirrors the agentic "max_loop" concept: an agent (or cron job)
#   should never recurse unboundedly. Each iteration is one symlink examined.
#   If MAX_ITERATIONS is hit, the script exits cleanly with a state file
#   so the *next* scheduled run (next agent context) continues from there.
#   Bounded work per context. Persistent state across contexts.
#   See: .ai/patterns/bounded-iteration.md

set -eu

# ── Configuration ─────────────────────────────────────────────────────────────
MAX_ITERATIONS=200          # max symlinks examined per run (agent loop guard)
DRY_RUN=1                   # 1=detect only, 0=fix (set via --fix flag)
LOG_FILE="/var/log/fix-symlink-loops.log"
STATE_FILE="/tmp/fix-symlink-loops.state"  # cursor for cross-run continuity
MARKER_SUFFIX=".removed.symlink.txt"

# ── Safeguard: system paths never touched ────────────────────────────────────
# Intentional symlinks used by the OS/QTS — never resolve these.
# See: .ai/patterns/scope-safeguards.md
SYSTEM_EXCLUDES="
/bin
/sbin
/usr
/lib
/lib64
/proc
/sys
/dev
/run
/tmp
/etc
/opt/etc
/share/CACHEDEV
/share/.qpkg
/.qpkg
/mnt/ext
"

# ── Parse arguments ───────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --fix)     DRY_RUN=0 ;;
    --reset)   rm -f "$STATE_FILE" ; echo "State reset." ; exit 0 ;;
    --help|-h)
      echo "Usage: $0 [--fix] [--reset]"
      echo "  (no flags)  Detect loops only, report to $LOG_FILE"
      echo "  --fix       Remove loop-causing symlinks, leave .removed.symlink.txt marker"
      echo "  --reset     Clear iteration state (start from beginning next run)"
      exit 0 ;;
  esac
done

# ── Logging ───────────────────────────────────────────────────────────────────
log() { printf '%s [fix-symlink-loops] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$LOG_FILE" ; }

# ── Collect export roots ──────────────────────────────────────────────────────
collect_export_roots() {
  roots=""

  # Samba shares: path = /some/dir lines
  if [ -f /etc/samba/smb.conf ]; then
    samba_paths=$(grep -i '^\s*path\s*=' /etc/samba/smb.conf \
      | sed 's/.*=\s*//' | tr -d ' \t\r' | sort -u)
    roots="$roots $samba_paths"
    log "Samba roots: $(echo $samba_paths | tr '\n' ' ')"
  fi

  # NFS exports: first field per non-comment line
  if [ -f /etc/exports ]; then
    nfs_paths=$(grep -v '^\s*#' /etc/exports | grep -v '^\s*$' \
      | awk '{print $1}' | sort -u)
    roots="$roots $nfs_paths"
    log "NFS roots: $(echo $nfs_paths | tr '\n' ' ')"
  fi

  # QNAP: also check /etc/config/smb.conf fallback
  if [ -f /etc/config/smb.conf ]; then
    qnap_paths=$(grep -i '^\s*path\s*=' /etc/config/smb.conf \
      | sed 's/.*=\s*//' | tr -d ' \t\r' | sort -u)
    roots="$roots $qnap_paths"
  fi

  printf '%s' "$roots" | tr ' ' '\n' | grep '^/' | sort -u
}

# ── Safeguard: is path under a system-protected prefix? ──────────────────────
is_system_path() {
  target="$1"
  for excl in $SYSTEM_EXCLUDES; do
    case "$target" in
      "$excl"|"$excl/"*)
        return 0 ;;  # yes, system path — skip
    esac
  done
  return 1  # safe to process
}

# ── Detect if symlink target is an ancestor of the symlink itself ─────────────
is_loop_symlink() {
  link_path="$1"
  link_dir=$(dirname "$link_path")
  target=$(readlink "$link_path")

  # Resolve relative targets
  case "$target" in
    /*) abs_target="$target" ;;
    *)  abs_target="$link_dir/$target" ;;
  esac

  # Normalize (remove ./ ../ etc) — POSIX compatible
  abs_target=$(cd -P "$(dirname "$abs_target")" 2>/dev/null \
    && printf '%s/%s' "$(pwd)" "$(basename "$abs_target")" \
    || printf '%s' "$abs_target")

  # Loop if target == link_dir, or link_dir starts with target/
  case "$link_dir" in
    "$abs_target"|"$abs_target/"*) return 0 ;;
  esac

  # Also loop if target is a child that already contains the link
  case "$abs_target" in
    "$link_dir"|"$link_dir/"*) return 0 ;;
  esac

  return 1
}

# ── Write marker file — see .ai/patterns/marker-as-memory.md ─────────────────
write_marker() {
  link_path="$1"
  target=$(readlink "$link_path")
  marker="${link_path}${MARKER_SUFFIX}"

  cat > "$marker" << EOF
REMOVED SYMLINK — $(date '+%Y-%m-%dT%H:%M:%S')
================================================
This file was created by fix-symlink-loops.sh because the symlink at this
location caused a circular directory loop visible over Samba/NFS to Windows
clients, resulting in apparently infinite recursive folder trees.

Original symlink : $link_path
Pointed to       : $target
Removed by       : fix-symlink-loops.sh (dotfiles-macos/qnap/)
Action           : symlink removed; this marker file left in its place

If this symlink was intentional, restore it with:
  ln -s "$target" "$link_path"
  rm "$marker"

Agent loop guard note:
  This resolution is idempotent. Re-running the script will not re-remove
  an already-resolved link (marker file presence is checked first).
  See: .ai/patterns/marker-as-memory.md
EOF
  log "MARKER written: $marker"
}

# ── Main loop — agent-bounded iteration ──────────────────────────────────────
main() {
  log "=== START run (DRY_RUN=$DRY_RUN, MAX_ITERATIONS=$MAX_ITERATIONS) ==="

  export_roots=$(collect_export_roots)
  if [ -z "$export_roots" ]; then
    log "No Samba/NFS export roots found — nothing to scan. Exiting."
    exit 0
  fi

  iteration=0
  found_loops=0
  fixed=0

  for root in $export_roots; do
    [ -d "$root" ] || continue
    is_system_path "$root" && { log "SKIP system root: $root" ; continue ; }

    log "Scanning: $root"

    find "$root" -xdev -type l 2>/dev/null | while IFS= read -r link; do

      # ── Agent loop guard ─────────────────────────────────────────────────
      iteration=$((iteration + 1))
      if [ "$iteration" -ge "$MAX_ITERATIONS" ]; then
        log "LOOP GUARD: MAX_ITERATIONS ($MAX_ITERATIONS) reached. Saving state."
        printf '%s\n' "$link" > "$STATE_FILE"
        log "Remaining work continues next run. See .ai/patterns/bounded-iteration.md"
        exit 0
      fi

      # Skip already-resolved markers (idempotency)
      marker="${link}${MARKER_SUFFIX}"
      [ -f "$marker" ] && continue

      # Skip system paths
      is_system_path "$link" && continue

      target=$(readlink "$link" 2>/dev/null) || continue
      [ -z "$target" ] && continue

      if is_loop_symlink "$link"; then
        found_loops=$((found_loops + 1))
        log "LOOP DETECTED: $link -> $target"

        if [ "$DRY_RUN" -eq 0 ]; then
          write_marker "$link"
          rm "$link"
          log "FIXED: removed $link"
          fixed=$((fixed + 1))
        else
          log "DRY-RUN: would remove $link"
        fi
      fi
    done
  done

  log "=== DONE: found=$found_loops fixed=$fixed iterations=$iteration ==="
  rm -f "$STATE_FILE"
}

main
