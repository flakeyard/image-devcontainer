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

predicate=${PREDICATE:-https://slsa.dev/provenance/v1}
args=(--repo "$REPOSITORY" --signer-workflow "$REPOSITORY/.github/workflows/release.yaml"
  --deny-self-hosted-runners --predicate-type "$predicate")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
if gh attestation verify "oci://$IMAGE@$DIGEST" "${args[@]}" >/dev/null 2>"$work/verify"; then
  echo "attested=true" >>"$GITHUB_OUTPUT"
  exit 0
fi

# Does any attestation of this predicate type exist for the digest? A 404 of
# the listing itself means none. The count fails on an attestation whose bundle
# is not inline, rather than miss it.
if ! gh api "repos/$REPOSITORY/attestations/$DIGEST" >"$work/list" 2>"$work/listing"; then
  if ! grep -qF 'HTTP 404' "$work/listing"; then
    echo "error: cannot list the attestations of $DIGEST: $(cat "$work/listing")" >&2
    exit 1
  fi
  echo '{"attestations": []}' >"$work/list"
fi
existing=$(jq --arg type "$predicate" '
  def statement: .bundle.dsseEnvelope.payload | @base64d | fromjson;
  .attestations
  | if any(.bundle == null) then error("an attestation of the digest has no inline bundle")
    else map(select(statement.predicateType == $type)) | length end' "$work/list")
if ((existing > 0)); then
  echo "error: $DIGEST has $existing $predicate attestations, but none verifies: $(cat "$work/verify")" >&2
  exit 1
fi
echo "attested=false" >>"$GITHUB_OUTPUT"
