#!/bin/sh
# list-extensions-by-dir.sh
# List all unique file extensions grouped by directory, excluding .git
# Usage: sh list-extensions-by-dir.sh [directory]
#
# Output: directory path followed by its extensions, sorted

TARGET="${1:-.}"

find "$TARGET" -type f -not -path '*/.git/*' \
  | awk -F/ '{
    n = NF - 1
    dir = ""
    for (i = 2; i <= n; i++) dir = dir "/" $i
    if (dir == "") dir = "(root)"
    file = $NF
    ext = (file ~ /\./) ? substr(file, index(file, ".")) : "(none)"
    sub(/.*\./, ".", ext)
    print dir "\t" ext
  }' \
  | sort \
  | uniq \
  | awk -F'\t' '
    prev != $1 { if (prev != "") print ""; print $1 ":"; prev = $1 }
    { printf "  %s\n", $2 }
  '
