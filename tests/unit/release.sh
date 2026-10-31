#!/usr/bin/env bash
# shellcheck disable=SC2016 # check evaluates its expression later
# Unit tests of .github/scripts with a stub of gh. Inputs (environment):
# SCRIPTS (.github/scripts), STUBS.
set -uo pipefail
export LC_ALL=C

failed=0 passed=0 current=""

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls NOTES=$work/notes GITHUB_OUTPUT=$work/output PATH=$STUBS:$PATH
  export GH_TOKEN=t REPOSITORY=flakeyard/image-devcontainer IMAGE=ghcr.io/flakeyard/image-devcontainer
  export TAG=v1.2.3 REFERENCE="ghcr.io/flakeyard/image-devcontainer:v1.2.3@sha256:abc"
  export DIGEST=sha256:abc PREDICATE=""
  unset ATTESTED
  : >"$CALLS"
  : >"$GITHUB_OUTPUT"
  printf '## 1.2.3\n\n### Features\n\n* something\n' >"$NOTES"
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

check() {
  [[ -n $current ]] || return 0
  eval "$1" || report "$2"
}

finish() {
  if [[ -n $current ]]; then passed=$((passed + 1)); fi
  current=""
  rm -rf -- "$work"
}

# --- annotate-release --------------------------------------------------------------

setup
run "annotate-release: adds the image to the notes" ok "$SCRIPTS/annotate-release.sh"
check 'grep -qxF "Image: \`$REFERENCE\`" "$NOTES"' "notes: $(cat "$NOTES")"
check 'grep -qxF "* something" "$NOTES"' "the old notes are gone"
finish

setup
run "annotate-release: adds it once" ok "$SCRIPTS/annotate-release.sh"
: >"$CALLS"
run "annotate-release: a rerun changes nothing" ok "$SCRIPTS/annotate-release.sh"
check '[[ ! -s $CALLS ]]' "edited again"
check '[[ $(grep -c "^Image:" "$NOTES") == 1 ]]' "notes: $(cat "$NOTES")"
finish

# --- attested -----------------------------------------------------------------------

setup
export ATTESTED=1
run "attested: true when an attestation verifies" ok "$SCRIPTS/attested.sh"
check 'grep -qx attested=true "$GITHUB_OUTPUT"' "output: $(cat "$GITHUB_OUTPUT")"
check 'grep -qF -- "--signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml" "$CALLS"' "calls: $(cat "$CALLS")"
finish

setup
run "attested: false otherwise" ok "$SCRIPTS/attested.sh"
check 'grep -qx attested=false "$GITHUB_OUTPUT"' "output: $(cat "$GITHUB_OUTPUT")"
finish

setup
export ATTESTED=1 PREDICATE=https://cyclonedx.org/bom
run "attested: checks the predicate type of an SBOM" ok "$SCRIPTS/attested.sh"
check 'grep -qF -- "--predicate-type https://cyclonedx.org/bom" "$CALLS"' "calls: $(cat "$CALLS")"
finish

echo "passed: $passed, failed: $failed"
((failed == 0))
