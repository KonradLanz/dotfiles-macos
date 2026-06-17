# fix-symlink-loops.sh — AI Sidecar

## Purpose
Detects and optionally resolves circular symlinks in directories exported via
Samba (`smb.conf`) or NFS (`/etc/exports`) on QNAP / POSIX systems.

Triggered by: two self-referencing symlinks found in
`KG/Steuer/Rechnungen/` on a QNAP NAS causing infinite directory trees
in Windows Explorer over SMB.

```
./KG/Steuer/Rechnungen/Rechnungen -> /share/NFSv=4/homes/.../KG/Steuer/Rechnungen
./KG/Steuer/Rechnungen/Steuer     -> /share/NFSv=4/homes/.../KG/Steuer
```

## Key Design Decisions

### Scoped to export roots only
Reads `/etc/samba/smb.conf`, `/etc/config/smb.conf` (QNAP), and
`/etc/exports` to determine which directories are actually shared.
Never touches anything outside these paths; skips known system prefixes
as an additional safeguard. See `.ai/patterns/scope-safeguards.md`.

### Loop detection heuristic
A symlink is circular if its resolved absolute target is a **directory
ancestor** of the symlink itself, or vice versa. Minimal POSIX-safe
heuristic; no false-positives on intentional cross-device/cross-tree links.

### Idempotent marker pattern
`--fix` replaces the symlink with `<name>.removed.symlink.txt` describing
what was there, why it was removed, and how to restore it. Re-running
skips paths where the marker already exists.
See `.ai/patterns/marker-as-memory.md`.

### Agent loop guard / MAX_ITERATIONS
`MAX_ITERATIONS` (default 200) bounds symlinks examined per run.
When the limit is hit, current position is saved to a state file;
the next cron run resumes from there.
See `.ai/patterns/bounded-iteration.md`.

## NFS vs Samba
Both protocols expose the same POSIX symlink problem:
- **Samba**: Windows clients follow symlinks as directories (with `follow symlinks = yes`)
- **NFS**: Linux/macOS clients hit `ELOOP` and stop; Windows via Samba loops forever

The fix is identical for both; scope is determined by export configuration.

## Cronjob (QNAP)
```sh
# /etc/config/crontab
# Daily 03:15 — detect only
15 3 * * * /share/homes/DOMAIN=AD/koni/scripts/fix-symlink-loops.sh
# Sunday 04:00 — fix mode
0 4 * * 0 /share/homes/DOMAIN=AD/koni/scripts/fix-symlink-loops.sh --fix

# Reload:
crontab /etc/config/crontab && /etc/init.d/crond.sh restart
```

## dotfiles-macos placement
`qnap/fix-symlink-loops.sh` — POSIX-portable, QNAP-targeted,
part of the storage hygiene toolchain alongside `ai-checksum.sh`.

## Related patterns
- `.ai/patterns/bounded-iteration.md`
- `.ai/patterns/scope-safeguards.md`
- `.ai/patterns/marker-as-memory.md`
