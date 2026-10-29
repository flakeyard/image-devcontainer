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

# --- check-eol ----------------------------------------------------------------

for case in "2026-10-29 ok supported" "2026-12-10 ok in 21 days" "2027-01-02 fail reached its end of life"; do
  read -r today expected message <<<"$case"
  setup
  printf '# comment\nnixos-26.05 2026-12-31\n' >"$work/eol"
  run "eol: $today" "$expected" "$SCRIPTS/check-eol.sh" "$work/eol" "$today"
  expect message "$message"
  finish
done

# --- check-release-rebuild -----------------------------------------------------------

# rebuild: runs check-release-rebuild in the repository of the test.
rebuild() { (cd "$work/repo" && "$SCRIPTS/check-release-rebuild.sh" ghcr.io/x/y amd64); }

# release_setup: a git repository with the tag v1.0.0 and a registry that
# publishes it with the platform digests of the stub.
release_setup() {
  setup
  TARBALL_DIGEST=sha256:$(printf 'a%.0s' {1..64})
  export REGISTRY=$work/registry TARBALL_DIGEST
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags" "$work/repo"
  git -C "$work/repo" init -q
  # Independent of the git configuration of whoever runs the tests.
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git -C "$work/repo" -c commit.gpgsign=false commit -q --allow-empty -m init
  git -C "$work/repo" -c tag.gpgsign=false tag v1.0.0
  index=$(printf '{"manifests":[{"digest":"%s","platform":{"architecture":"amd64"}}]}' "$TARBALL_DIGEST")
  printf '%s' "$index" >"$REGISTRY/manifests/sha256:index"
  echo sha256:index >"$REGISTRY/tags/v1.0.0"
}

release_setup
run "release-rebuild: the rebuild has the published digest" ok rebuild
expect message "v1.0.0 rebuilt for amd64 has the published digest"
finish

release_setup
TARBALL_DIGEST=sha256:$(printf 'b%.0s' {1..64})
run "release-rebuild: another digest fails" fail rebuild
expect message "the registry has sha256:aaaa"
finish

release_setup
git -C "$work/repo" tag -d v1.0.0 >/dev/null
run "release-rebuild: nothing to do before the first release" ok rebuild
expect message "No release"
finish

release_setup
rm -r "$REGISTRY/tags"
run "release-rebuild: a release missing from the registry fails" fail rebuild
finish

release_setup
export CRANE_DENIED=1
run "release-rebuild: other registry errors fail" fail rebuild
expect message "DENIED"
unset CRANE_DENIED
finish

release_setup
run "release-rebuild: uses the tools of the release" ok rebuild
[[ -z $current ]] || grep -q '/source#platform-digest -- ' "$CALLS" || report "calls: $(cat "$CALLS")"
finish

echo "passed: $passed, failed: $failed"
((failed == 0))
