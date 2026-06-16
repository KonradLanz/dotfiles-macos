# setup-hide-notch.sh
> Installs `notch-black.swift` as a Login LaunchAgent with wallpaper backup on first run; also handles clean uninstall.

## 0. Entry points
- `--uninstall` branch is at the top of the install/uninstall dispatch.
- Backup logic starts at the `# Aktuelles Wallpaper sichern` block.
- LaunchAgent plist is written via heredoc around the `cat > "$LAUNCH_AGENT_PLIST"` line.
- Related files: `display/notch-black.swift`, `display/setup-hide-notch.sh.ai.md`
- Known good commands:
  - `cd ~/git/dotfiles-macos && ./display/setup-hide-notch.sh`
  - `./display/setup-hide-notch.sh --uninstall`

## 1. Purpose
One-shot installer that backs up the current wallpaper, writes a LaunchAgent plist to `~/Library/LaunchAgents/`, and starts the agent immediately. On uninstall: stops agent, restores wallpaper from newest backup, cleans up temp files.

## 2. Structure
- Config block: paths for script, plist, backup dir, temp PNG, log files
- Output helpers: `info`, `success`, `warn`, `error`, `header` (colour-coded)
- Uninstall branch: stop agent → delete plist → SIGTERM swift script → restore from backup
- Install branch: backup current wallpaper → prune to 10 backups → write plist → `launchctl load`
- Backup format: `wallpaper_YYYY-MM-DD_HH-MM-SS_<name>.backup` + `.backup.path` sidecar

## 3. Interfaces
- Reads: current wallpaper via `swift -e NSWorkspace.desktopImageURL` (primary) with `osascript/Finder` fallback
- Writes: `~/Library/Application Support/hide-notch/backups/*.backup` + `.backup.path`
- Writes: `~/Library/Application Support/hide-notch/backups/.last_hash` (SHA256 for deduplication)
- Writes: `~/Library/LaunchAgents/com.koni.hide-notch.plist`
- Logs: `/tmp/hide-notch.log`, `/tmp/hide-notch.err`
- Parameters: `--uninstall` (no other flags)

## 4. Change notes
- Stable: backup format, 10-backup retention, LaunchAgent label `com.koni.hide-notch`
- Fixed: wallpaper detection now uses `NSWorkspace.desktopImageURL` inline Swift (consistent with `notch-black.swift`); `osascript/Finder` kept as fallback only
- Fixed: SHA256 hash deduplication via `.last_hash` — no backup created when wallpaper unchanged
- Fixed: `cp -c` (APFS Copy-on-Write clone) instead of `cp` — backup is instant and costs zero extra bytes until modified
- Fixed: backup cleanup loop now uses `while read` instead of broken `xargs … rm "{}" "{}" .path`
