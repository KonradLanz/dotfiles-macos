# dotfiles-macos

## Menu bar state tracking

Track macOS menu bar and notch-related configuration so regressions can be compared across updates and used in bug reports.

### Snapshot artifacts

- `~/Library/Preferences/com.apple.systemuiserver.plist`
- `~/Library/Preferences/com.apple.controlcenter.plist`
- `~/Library/Preferences/ByHost/com.apple.systemuiserver*.plist`
- `~/Library/Preferences/ByHost/com.apple.controlcenter*.plist`
- `~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist`

### Supplemental metadata

- `sw_vers`
- `system_profiler SPDisplaysDataType`
- visible menu bar items before and after updates

### Purpose

This is meant to preserve evidence for bugs such as TopNotch-style notch/menu bar regressions, icon overflow, Control Center layout changes, and other macOS update-related UI issues.
