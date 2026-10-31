#!/usr/bin/env bash
# Unit tests of scripts/check/size.sh, with a stub of nix and a fake image
# stream. Inputs (environment): SCRIPTS, the scripts directory; STUBS, the
# stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

setup() {
  work=$(mktemp -d)
  export STREAM=$work/stream SYSTEM=x86_64-linux
  export PATH=$STUBS:$PATH
  # A stream of 3 MiB.
  cat >"$STREAM" <<STREAM
#!$(command -v bash)
head -c 3145728 /dev/zero
STREAM
  chmod +x "$STREAM"
}

setup
printf '# comment\nx86_64-linux 3\naarch64-linux 1\n' >"$work/budget"
run "size: within the budget" ok "$SCRIPTS/check/size.sh" "$work/budget"
expect message "is 3 MiB (3145728 bytes); its budget is 3 MiB"
finish

setup
printf 'x86_64-linux 2\n' >"$work/budget"
run "size: over the budget" fail "$SCRIPTS/check/size.sh" "$work/budget"
expect message "exceeds its budget"
finish

setup
SYSTEM=aarch64-linux
printf 'x86_64-linux 3\n' >"$work/budget"
run "size: no budget for the system" fail "$SCRIPTS/check/size.sh" "$work/budget"
expect message "no budget for aarch64-linux"
finish

summary
