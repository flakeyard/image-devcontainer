#!/usr/bin/env bash
# Writes attested=true to $GITHUB_OUTPUT when an attestation of the release
# workflow for the release commit verifies for the digest, so that a rerun
# creates no new one (FY-0027); attested=false when the digest has no
# attestation of that predicate type. Fails otherwise: an attestation that
# exists but does not verify, or an error, must not lead to another one.
# Inputs (environment): GH_TOKEN, REPOSITORY (owner/name), IMAGE (registry
# repository), DIGEST, REVISION (the release commit), PREDICATE (empty for
# provenance).
set -euo pipefail
shopt -s inherit_errexit

predicate=${PREDICATE:-https://slsa.dev/provenance/v1}
args=(--repo "$REPOSITORY" --signer-workflow "$REPOSITORY/.github/workflows/release.yaml"
  --source-digest "$REVISION" --deny-self-hosted-runners --predicate-type "$predicate")
errors=$(mktemp)
trap 'rm -f -- "$errors"' EXIT
if gh attestation verify "oci://$IMAGE@$DIGEST" "${args[@]}" >/dev/null 2>"$errors"; then
  echo "attested=true" >>"$GITHUB_OUTPUT"
  exit 0
fi

# Does any attestation of this predicate type exist for the digest?
if ! payloads=$(gh api "repos/$REPOSITORY/attestations/$DIGEST" \
  --jq '.attestations[].bundle.dsseEnvelope.payload' 2>>"$errors"); then
  if grep -q 'HTTP 404' "$errors"; then
    payloads=""
  else
    echo "error: cannot list the attestations of $DIGEST: $(cat "$errors")" >&2
    exit 1
  fi
fi
existing=0
while IFS= read -r payload; do
  [[ -n $payload ]] || continue
  if [[ $(base64 -d <<<"$payload" | jq -r .predicateType) == "$predicate" ]]; then
    existing=$((existing + 1))
  fi
done <<<"$payloads"
if ((existing > 0)); then
  echo "error: $DIGEST has $existing $predicate attestations, but none verifies: $(cat "$errors")" >&2
  exit 1
fi
echo "attested=false" >>"$GITHUB_OUTPUT"
