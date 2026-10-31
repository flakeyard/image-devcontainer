#!/usr/bin/env bash
# Writes attested=true to $GITHUB_OUTPUT when an attestation of the release
# workflow verifies for the digest, so that a rerun creates no new one
# (FY-0027); attested=false when the digest has no attestation of that
# predicate type. Fails otherwise: an attestation that exists but does not
# verify, or an error, must not lead to another one.
# The attestation is not bound to a commit: a release that leaves the image
# unchanged reuses that of the release that first published the digest.
# Inputs (environment): GH_TOKEN, REPOSITORY (owner/name), IMAGE (registry
# repository), DIGEST, PREDICATE (empty for provenance).
set -euo pipefail
shopt -s inherit_errexit

readonly provenance=https://slsa.dev/provenance/v1
readonly not_found='HTTP 404'
predicate=${PREDICATE:-$provenance}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

fail() {
  echo "error: $1" >&2
  exit 1
}

set_output() {
  local attested=$1
  echo "attested=$attested" >>"$GITHUB_OUTPUT"
}

# Keeps the errors of the verification in $work/verify.
verifies() {
  gh attestation verify "oci://$IMAGE@$DIGEST" --repo "$REPOSITORY" \
    --signer-workflow "$REPOSITORY/.github/workflows/release.yaml" \
    --deny-self-hosted-runners --predicate-type "$predicate" >/dev/null 2>"$work/verify"
}

# Prints the attestations of the digest as the API lists them; a 404 of the
# listing itself means none.
attestation_list() {
  local errors=$work/listing
  if gh api "repos/$REPOSITORY/attestations/$DIGEST" 2>"$errors"; then
    return 0
  fi
  grep -qF -- "$not_found" "$errors" ||
    fail "cannot list the attestations of $DIGEST: $(cat "$errors")"
  echo '{"attestations": []}'
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
((existing == 0)) ||
  fail "$DIGEST has $existing $predicate attestations, but none verifies: $(cat "$work/verify")"
set_output false
