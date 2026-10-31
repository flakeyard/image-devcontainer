#!/usr/bin/env bash
# Unit tests of scripts/check/reproducible.sh, with a stub of nix and a fake
# image stream. Inputs (environment): SCRIPTS, the scripts directory; STUBS,
# the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls STREAM=$work/stream
  export PATH=$STUBS:$PATH
  : >"$CALLS"
  # A stream of the image; with $work/vary, every run differs.
  cat >"$STREAM" <<STREAM
#!$(command -v bash)
echo image
if [[ -e $work/vary ]]; then date +%N; fi
STREAM
  chmod +x "$STREAM"
  export DRY_RUN="these 2 derivations will be built:
  /nix/store/aaaa-entrypoint.drv
  /nix/store/bbbb-stream.drv
these 300 paths will be fetched (100.00 MiB download, 400.00 MiB unpacked):
  /nix/store/cccc-glibc"
}

setup
run "reproducible: rebuilds the own derivations" ok "$SCRIPTS/check/reproducible.sh"
expect calls "build;rebuild --no-link --rebuild --keep-going /nix/store/aaaa-entrypoint.drv^* /nix/store/bbbb-stream.drv^*"
expect message "Rebuilding /nix/store/bbbb-stream.drv"
expect message "needs 2 derivations"
expect message "Two streams of the image are equal"
finish

setup
DRY_RUN="these 300 paths will be fetched (1.00 MiB download, 4.00 MiB unpacked):
  /nix/store/cccc-glibc"
run "reproducible: nothing to rebuild" ok "$SCRIPTS/check/reproducible.sh"
expect calls "build"
expect message "needs 0 derivations"
finish

setup
export REBUILD_ERROR="error: derivation '/nix/store/bbbb-stream.drv' may not be deterministic"
run "reproducible: a rebuild that differs fails" fail "$SCRIPTS/check/reproducible.sh"
expect message "bbbb-stream.drv' may not be deterministic"
unset REBUILD_ERROR
finish

setup
touch "$work/vary"
run "reproducible: different streams fail" fail "$SCRIPTS/check/reproducible.sh"
expect message "two streams of the image differ"
finish

summary
