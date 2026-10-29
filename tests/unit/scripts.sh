#!/usr/bin/env bash
# Unit tests of scripts/, with a stub of nix and a fake image stream.
# Inputs (environment): SCRIPTS, the scripts directory; STUBS, the stubs.
set -uo pipefail
export LC_ALL=C

failed=0 passed=0 current=""

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls STREAM=$work/stream SYSTEM=x86_64-linux
  export PATH=$STUBS:$PATH
  : >"$CALLS"
  # A stream of 3 MiB; with $work/vary, every run differs.
  cat >"$STREAM" <<STREAM
#!$(command -v bash)
head -c 3145728 /dev/zero
if [[ -e $work/vary ]]; then date +%N; fi
STREAM
  chmod +x "$STREAM"
  export DRY_RUN="these 2 derivations will be built:
  /nix/store/aaaa-entrypoint.drv
  /nix/store/bbbb-stream.drv
these 300 paths will be fetched (100.00 MiB download, 400.00 MiB unpacked):
  /nix/store/cccc-glibc"
}

run() {
  local name=$1 expected=$2 status=0
  shift 2
  "$@" >"$work/out" 2>&1 || status=$?
  current=$name
  if [[ $expected == ok && $status != 0 ]] || [[ $expected == fail && $status == 0 ]]; then
    report "expected $expected, exit $status: $(cat "$work/out")"
  fi
}

report() {
  [[ -n $current ]] || return 0
  echo "FAIL $current: $1"
  failed=$((failed + 1))
  current=""
}

expect() {
  [[ -n $current ]] || return 0
  case $1 in
    message) grep -qF -- "$2" "$work/out" || report "no message '$2' in: $(cat "$work/out")" ;;
    calls) [[ $(paste -sd';' "$CALLS") == "$2" ]] || report "calls '$(paste -sd';' "$CALLS")', expected '$2'" ;;
  esac
}

finish() {
  if [[ -n $current ]]; then passed=$((passed + 1)); fi
  current=""
  rm -rf -- "$work"
}

# --- check-reproducible --------------------------------------------------------

setup
run "reproducible: rebuilds the own derivations" ok "$SCRIPTS/check-reproducible.sh"
expect calls "build;rebuild /nix/store/aaaa-entrypoint.drv^*;rebuild /nix/store/bbbb-stream.drv^*"
expect message "needs 2 derivations"
expect message "Two streams of the image are equal"
finish

setup
DRY_RUN="these 300 paths will be fetched (1.00 MiB download, 4.00 MiB unpacked):
  /nix/store/cccc-glibc"
run "reproducible: nothing to rebuild" ok "$SCRIPTS/check-reproducible.sh"
expect calls "build"
expect message "needs 0 derivations"
finish

setup
touch "$work/vary"
run "reproducible: different streams fail" fail "$SCRIPTS/check-reproducible.sh"
expect message "two streams of the image differ"
finish

# --- check-size ---------------------------------------------------------------

setup
printf '# comment\nx86_64-linux 3\naarch64-linux 1\n' >"$work/budget"
run "size: within the budget" ok "$SCRIPTS/check-size.sh" "$work/budget"
expect message "is 3 MiB (3145728 bytes); its budget is 3 MiB"
finish

setup
printf 'x86_64-linux 2\n' >"$work/budget"
run "size: over the budget" fail "$SCRIPTS/check-size.sh" "$work/budget"
expect message "exceeds its budget"
finish

setup
SYSTEM=aarch64-linux
printf 'x86_64-linux 3\n' >"$work/budget"
run "size: no budget for the system" fail "$SCRIPTS/check-size.sh" "$work/budget"
expect message "no budget for aarch64-linux"
finish

echo "passed: $passed, failed: $failed"
((failed == 0))
