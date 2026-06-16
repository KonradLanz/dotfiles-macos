# mcp-filelist.sh
> Produces an ignore-aware file inventory summary so an AI can quickly infer relevant file types, priority files, and likely watch targets without crawling the full repo tree.

## 0. Entry points
- Start at the root/ignore/context parameter block.
- Core flow: build ignore list, scan files, compute extension histogram, print priority files and watch guidance.
- Related files: `.mcpignore`, `.mcp-context.md`, `.ai/ignore` (future alignment).
- Known good command: `bash mcp-filelist.sh ~/git/dotfiles-macos`.

## 1. Purpose
This script gives a fast structural overview of a repo and helps decide what should be watched, ignored, or read first.

## 2. Structure
- Resolve root, ignore file, and context file.
- Merge built-in ignore defaults with user ignore rules.
- Scan files while excluding ignored paths.
- Print markdown sections for suggested watch types, extension histogram, priority files, watch recommendations, and active ignore rules.

## 3. Interfaces
- Reads: `.mcpignore`, `.mcp-context.md`.
- Outputs: markdown to stdout.
- Parameters: repo root, optional ignore file, optional context file.

## 4. Change notes
- Stable: ignore-aware repo summary role.
- Likely to change: performance, ignore matching semantics, and alignment with `.ai` sidecar/index files.
