#!/usr/bin/env bash
# Writes attested=true to $GITHUB_OUTPUT when an attestation of the release
# workflow verifies for the digest, so that a rerun creates no new one
# (FY-0032); attested=false when the digest has no attestation of that
# predicate type. Fails otherwise: an attestation that exists but does not
# verify, or an error, must not lead to another one.
# The attestation is not bound to a commit: a release that leaves the image
# unchanged reuses that of the release that first published the digest.
# Inputs (environment): GH_TOKEN, REPOSITORY (owner/name), IMAGE (registry
# repository), DIGEST, PREDICATE (empty for provenance), SHELL_LIB (the
# directory of the shell library).
set -euo pipefail
shopt -s inherit_errexit
# The checks of the publish apps, from the same commit as this action.
# shellcheck source=/dev/null # scripts/publish/lib.sh
source "${BASH_SOURCE[0]%/*}/../../../scripts/publish/lib.sh"
# Calls of the GitHub API, from the shell library that the job pins.
# shellcheck source=/dev/null # github/api.sh of the library
source "$SHELL_LIB/github/api.sh"

readonly provenance=https://slsa.dev/provenance/v1
predicate=${PREDICATE:-$provenance}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

set_output() {
  local attested=$1
  echo "attested=$attested" >>"$GITHUB_OUTPUT"
}

# Keeps the errors of the verification in $work/verify.
verifies() {
  verify_attestation "$REPOSITORY" "$IMAGE" "$DIGEST" --predicate-type "$predicate" 2>"$work/verify"
}

# Prints the attestations of the digest as the API lists them; a 404 of the
# listing itself means none. fail of lib.sh writes to stderr, so its message
# is not lost in the command substitution of the caller.
attestation_list() {
  local status=0
  api_request GET "repos/$REPOSITORY/attestations/$DIGEST" || status=$?
  case $status in
    0) ;;
    "$NOT_FOUND") echo '{"attestations": []}' ;;
    *) fail "cannot list the attestations of $DIGEST" ;;
  esac
}

# Fails on an attestation whose bundle is not inline, rather than miss it.
count_of_predicate() {
  local list
  list=$(attestation_list)
  jq --arg type "$predicate" '
    def statement: .bundle.dsseEnvelope.payload | @base64d | fromjson;
    def inline: if .bundle == null then error("an attestation of the digest has no inline bundle") else . end;
    [.attestations[] | inline | select(statement.predicateType == $type)] | length' <<<"$list"
}

if verifies; then
  set_output true
  exit 0
fi
existing=$(count_of_predicate)
((existing == 0)) \
  || fail "$DIGEST has $existing $predicate attestations, but none verifies: $(cat "$work/verify")"
set_output false
