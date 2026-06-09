#!/bin/sh
# list-extensions-simple.sh
# List all unique file extensions recursively, excluding .git
# Usage: sh list-extensions-simple.sh [directory]
#
# Output: one extension per line, sorted and deduplicated

TARGET="${1:-.}"

find "$TARGET" -type f -not -path '*/.git/*' \
  | sed 's/.*\.//' \
  | sort -u
