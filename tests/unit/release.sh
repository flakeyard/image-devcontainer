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
  unset ATTESTED ATTESTATIONS GH_API_ERROR
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

provenance=https://slsa.dev/provenance/v1
bom=https://cyclonedx.org/bom

setup
export ATTESTED=1
run "attested: true when an attestation verifies" ok "$SCRIPTS/attested.sh"
check 'grep -qx attested=true "$GITHUB_OUTPUT"' "output: $(cat "$GITHUB_OUTPUT")"
check 'grep -qF -- "--signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml" "$CALLS"' "calls: $(cat "$CALLS")"
check '! grep -qF -- "--source-digest" "$CALLS"' "bound to a commit: $(cat "$CALLS")"
check 'grep -qF -- "--deny-self-hosted-runners" "$CALLS"' "self-hosted runners allowed: $(cat "$CALLS")"
finish

setup
export ATTESTED=1 ATTESTATIONS="$provenance $bom"
run "attested: an unchanged image reuses the previous release's attestation" ok "$SCRIPTS/attested.sh"
check 'grep -qx attested=true "$GITHUB_OUTPUT"' "output: $(cat "$GITHUB_OUTPUT")"
finish

setup
run "attested: false when the digest has no attestation" ok "$SCRIPTS/attested.sh"
check 'grep -qx attested=false "$GITHUB_OUTPUT"' "output: $(cat "$GITHUB_OUTPUT")"
finish

setup
export PREDICATE=$bom ATTESTATIONS=$provenance
run "attested: an SBOM is missing although provenance exists" ok "$SCRIPTS/attested.sh"
check 'grep -qx attested=false "$GITHUB_OUTPUT"' "output: $(cat "$GITHUB_OUTPUT")"
check 'grep -qF -- "--predicate-type $bom" "$CALLS"' "calls: $(cat "$CALLS")"
finish

setup
export ATTESTATIONS="$provenance $bom"
run "attested: an attestation that does not verify fails" fail "$SCRIPTS/attested.sh"
check 'grep -qF "none verifies" "$work/out"' "out: $(cat "$work/out")"
check '[[ ! -s $GITHUB_OUTPUT ]]' "output written: $(cat "$GITHUB_OUTPUT")"
finish

setup
export GH_API_ERROR=1
run "attested: an API error fails, whatever the verification reported" fail "$SCRIPTS/attested.sh"
check 'grep -qF "cannot list the attestations" "$work/out"' "out: $(cat "$work/out")"
check '[[ ! -s $GITHUB_OUTPUT ]]' "output written: $(cat "$GITHUB_OUTPUT")"
finish

setup
export ATTESTATIONS="- $provenance"
run "attested: an attestation without an inline bundle fails" fail "$SCRIPTS/attested.sh"
check 'grep -qF "no inline bundle" "$work/out"' "out: $(cat "$work/out")"
check '[[ ! -s $GITHUB_OUTPUT ]]' "output written: $(cat "$GITHUB_OUTPUT")"
finish

setup
export ATTESTATIONS=$bom
run "attested: an attestation of another type does not count" ok "$SCRIPTS/attested.sh"
check 'grep -qx attested=false "$GITHUB_OUTPUT"' "output: $(cat "$GITHUB_OUTPUT")"
finish

echo "passed: $passed, failed: $failed"
((failed == 0))
