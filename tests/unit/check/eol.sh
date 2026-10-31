#!/usr/bin/env bash
# Unit tests of scripts/check/eol.sh. Inputs (environment): SCRIPTS, the
# scripts directory.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

setup() { work=$(mktemp -d); }

for case in "2026-10-29 ok supported" "2026-12-10 ok in 21 days" "2027-01-02 fail reached its end of life"; do
  read -r today expected message <<<"$case"
  setup
  printf '# comment\nnixos-26.05 2026-12-31\n' >"$work/eol"
  run "eol: $today" "$expected" "$SCRIPTS/check/eol.sh" "$work/eol" "$today"
  expect message "$message"
  finish
done

# A malformed EOL file fails with a message instead of counting from today.
while IFS='|' read -r name content message; do
  setup
  printf '%b' "$content" >"$work/eol"
  run "eol: $name" fail "$SCRIPTS/check/eol.sh" "$work/eol" 2026-10-29
  expect message "$message"
  finish
done <<'CASES'
no date|# comment\nnixos-26.05\n|'' is not a date
an invalid date|nixos-26.05 2026-02-30\n|'2026-02-30' is not a date
another date format|nixos-26.05 31.12.2026\n|'31.12.2026' is not a date
no data line|# comment\n\n|no data line
an empty file||no data line
two data lines|nixos-26.05 2026-12-31\nnixos-26.11 2027-06-30\n|more than one data line
not a branch|2026-12-31\n|'2026-12-31' is not a branch
an extra field|nixos-26.05 2026-12-31 x\n|unexpected 'x'
CASES

setup
printf 'nixos-26.05 2026-12-31' >"$work/eol"
run "eol: a last line without a newline" ok "$SCRIPTS/check/eol.sh" "$work/eol" 2026-10-29
expect message "supported until 2026-12-31"
finish

setup
printf 'nixos-26.05 2026-12-31\n' >"$work/eol"
run "eol: an invalid today" fail "$SCRIPTS/check/eol.sh" "$work/eol" ""
expect message "'' is not a date"
finish

setup
run "eol: a missing file" fail "$SCRIPTS/check/eol.sh" "$work/none"
finish

summary
