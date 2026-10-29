#!/usr/bin/env bash
# Usage: check-eol EOL_FILE [TODAY]
#
# Warns from 30 days before the end of life of the nixpkgs branch in
# EOL_FILE ("<branch> <YYYY-MM-DD>") and fails after it (FY-0026). Run weekly,
# never as a required check, so that old commits keep passing.
set -euo pipefail
shopt -s inherit_errexit

read -r branch eol < <(grep -v '^#' "$1")
today=${2:-$(date -u +%F)}
days=$((($(date -u -d "$eol" +%s) - $(date -u -d "$today" +%s)) / 86400))
if ((days < 0)); then
  echo "::error::$branch reached its end of life on $eol; switch to the next stable branch."
  exit 1
elif ((days <= 30)); then
  echo "::warning::$branch reaches its end of life on $eol, in $days days; switch to the next stable branch."
else
  echo "$branch is supported until $eol, $days days from $today."
fi
