# Shell performance best practices

This document summarizes practical shell performance rules for `mcp-filelist.sh` and `.ai` helpers in `dotfiles-macos`.

## zsh vs posix sh vs bash

### Interactive shell

- **zsh** is excellent for interactive use (better completion, customization, path expansion), but has slower startup when loaded with many plugins (Oh My Zsh).
- **bash** is slightly faster at startup for simple scripts, with fewer features enabled by default.
- **dash** performs best on POSIX compliance tests and is the fastest shell for general script execution, except when subshell functionality is used heavily (where ksh can be faster).

### Script execution

For pure script performance, especially in CI or bootstrap scripts:
- **dash** is the fastest for typical script execution.
- **bash** and **zsh** are both fine for interactive scripts and most automation, but don't beat dash in raw speed.
- **zsh** outperforms bash in many test cases, sometimes 4×®, but this is more about features than raw POSIX speed.

Recommendation: use `#!/usr/bin/env bash` for scripts that need bash features, but consider `#!/bin/dash` for pure POSIX bootstrap scripts where maximum speed is critical.

## Pipes, filters, and logic patterns

### Minimize external commands

- It is **20–70×¹** faster to do string manipulation in memory using shell parametric expansion than calling external utilities like `cut`, `sed`, or `grep` inside loops.
- It is **10×¹** faster to read a file into memory as a string and use Bash regex tests on that string multiple times, instead of calling `grep` many times.
- Use a single `awk` to handle all of `sed`, `cut`, `grep`, `head`, etc. chains when possible; `awk` is very fast and more efficient than perl or python for typical file processing.

### Line-by-line processing

- It is **2×¹** faster to read a file into an array and loop through the array than to use `while read`:
  ```bash
  readarray -t array < file
  for i in "${array[@]}"; do
    ...
  done
  ```
- For line-by-line handling with patterns, it is **2×¹** faster to prefilter with `grep` to process only certain lines, instead of reading the whole file into a loop and selecting lines inside:
  ```bash
  while read -r line; do
    ...
  done < <(grep --extended-regexp "$re" file)
  ```

### Avoid excessive pipes

- Unix pipes are excellent, but too many in a chain (`command | grep | grep | cut | sed`) makes code slow; each pipe is an overhead.
- Use `awk` pattern matching to do multiple operations with one process instead of `grep` → `awk` chains.
- For large files, use `grep` to search for patterns and then pass them to `awk` to "edit"; `grep`'s searching algorithm is very good and fast.

### Built-ins vs binaries

- Use Shell built-ins, not binaries:
  ```bash
  echo          # not /usr/bin/echo
  printf        # not /usr/bin/printf
  [ ... ]       # not /usr/bin/test
  ```
- Use `printf` instead of `echo` if your shell provides it; `printf` is significantly faster.
- `echo` by itself is typically **30×¹** faster than explicitly executing `/bin/echo`.

### Shebang choice

- For scripts that need bash features: `#!/usr/bin/env bash`
- For pure POSIX bootstrap scripts where maximum speed is critical: `#!/bin/dash`

## Large files and directories

- If you run scripts on many small files, set up a RAM disk and copy the files to it (tmpfs). This can lead to massive speed gains.
- If you know the files beforehand, preload them into memory (vmtouch).
- If you have tasks that can be run concurrently, use GNU parallel for massive gains in performance.
- For file processing with `find` and `xargs`, use `-print0 | xargs -0` for safety with filenames.

## Language choice for heavy lifting

- For text manipulation, small files, and typical file processing: `awk` is very fast and more efficient than perl or python.
- For really large files, lots of regex, or extensive data manipulation: use `perl` (or C) for speed, as nothing replaces perl's speed in those cases.
- For shell scripting, try to use less external commands if Bash's internals can do the task (string manipulation, pattern matching).

## Summary for mcp-filelist.sh

In `mcp-filelist.sh`, prioritize:
- Single `awk` calls instead of long `grep | cut | sed` chains
- Shell parameter expansion for string manipulation
- Prefilter with `grep` before looping
- Built-ins over binaries
- `readarray` + `for` over `while read`
- For very large repo scans, consider `find -print0 | xargs -0` patterns

---

1. Sources: jaalto/project--shell-script-performance, Apple ShellScripting performance guide, Marcinc Pawlukiewicz bash-zsh comparison, H Küttler Unix Shell Scripting best practices, StackOverflow shell scripting optimization.
