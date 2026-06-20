# move-mountpoints.sh — AI Sidecar

## Purpose

Safely migrates a macOS mountpoint (directory used as a network/automount target) from one path to another, updating all configuration references automatically.

## Usage

```zsh
./move-mountpoints.sh <old_path> <new_path>
# Example:
./move-mountpoints.sh ~/nw ~/git/nw
```

## What It Does

1. **Validates** source exists and resolves absolute paths
2. **Backs up** all affected config files to `~/.mountpoints-backups/<timestamp>/`
3. **Moves** the directory (creates parent dirs as needed)
4. **Updates references** in:
   - Shell configs: `~/.zprofile`, `~/.zshrc`, `~/.bash_profile`, `~/.bashrc`
   - App configs: all files under `~/.config/`
   - LaunchAgents: `~/Library/LaunchAgents/*.plist`, `/Library/LaunchAgents/*.plist`
5. **Reloads** any LaunchAgents that were modified
6. **Flags** system files needing `sudo` (fstab, AutoFS) with exact commands
7. **Verifies** the migration succeeded
8. **Rolls back** automatically on any error

## What It Does NOT Handle Automatically

System-protected files require `sudo` — the script prints the exact commands:
- `/etc/fstab`
- `/etc/auto_master`, `/etc/auto_direct`, `/etc/auto_home`

After updating those, run: `sudo automount -vc`

## Design Decisions

- Handles both absolute paths (`/Users/koni/nw`) and tilde forms (`~/nw`) when updating shell configs
- Uses `grep -F` (fixed string, not regex) to avoid issues with special characters in paths
- LaunchAgents are reloaded live via `launchctl` after plist update
- Rollback restores config files from backup but cannot undo `mv` side effects beyond the directory itself
- Uses `set -e` + `trap ERR` for fail-fast rollback behavior

## Dependencies

- macOS zsh (standard)
- `sed`, `grep`, `find`, `cp`, `mv` (all standard macOS tools)
- `launchctl` (for LaunchAgent reload)
- `defaults` (for reading plist Label key)

## Known Limitations

- Does not scan Git repository configs (`.git/config` remotes use remote URLs, not local paths)
- Does not handle Spotlight indexing of the new path (macOS handles this automatically)
- Binary config files (e.g., some app plists) are not updated
