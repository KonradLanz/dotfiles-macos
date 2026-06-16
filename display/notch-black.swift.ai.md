# notch-black.swift
> Draws a black bar over the notch area of the wallpaper by painting a temporary PNG copy — the original wallpaper is never modified.

## 0. Entry points
- Start at the `loadOriginalURL` / `saveOriginalURL` functions for the state-file logic.
- Core geometry is the `fillScale / offsetY / visibleTopInImg / barHeightInImg` block.
- Signal handlers (`SIGTERM`, `SIGINT`) call `restoreWallpaper()` on exit.
- State file: `~/Library/Application Support/hide-notch/original-wallpaper.txt`
- Temp output: `/tmp/notch-wallpaper.png`
- Known good command: `swift display/notch-black.swift`

## 1. Purpose
Runs as a persistent process (via LaunchAgent) that on startup reads the current wallpaper, draws a black bar of exact notch height, writes a temp PNG, and sets it as the desktop image. Keeps the original path in a state file to survive restarts without reading its own output as input.

## 2. Structure
- State-file helpers: `loadOriginalURL`, `saveOriginalURL`
- Original-URL resolution: saved state has priority over `NSWorkspace.desktopImageURL`
- Screen geometry: `screenW/H` via `backingScaleFactor`, notch height via `safeAreaInsets.top`
- Image geometry: aspect-fill `fillScale`, `offsetY`, `visibleTopInImg`, `barHeightInImg`
- Rendering: `CGContext` draws original + black rect → `CGImageDestination` → temp PNG
- Desktop set: `NSWorkspace.setDesktopImageURL`
- Restore: `restoreWallpaper()` on SIGTERM/SIGINT, then `RunLoop.main.run()`

## 3. Interfaces
- Reads: `~/Library/Application Support/hide-notch/original-wallpaper.txt` (state)
- Writes: `/tmp/notch-wallpaper.png` (temp, overwritten each run)
- No CLI parameters — designed to be launched by LaunchAgent
- Safe on non-notch displays: `safeAreaInsets.top == 0` → no bar drawn

## 4. Change notes
- Stable: state-file anti-loop pattern, `safeAreaInsets.top` for notch height, aspect-fill geometry
- Likely to change: wallpaper URL detection should be unified with `setup-hide-notch.sh` (currently uses different method — see TODO)
- Resolved: `setup-hide-notch.sh` now uses inline Swift `NSWorkspace.desktopImageURL` as primary source (with `osascript/Finder` fallback) — both scripts now consistent
- Fixed: `originalURL` typo → `originalWallpaperURL` (line 67, caused compile error)
- Fixed: explicit `Double()` casts in `CGRect` fill call — Swift on macOS 26 resolved `-` operator ambiguously as `Duration` subtraction
