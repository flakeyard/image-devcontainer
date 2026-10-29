#!/usr/bin/env bash
# Writes attested=true to $GITHUB_OUTPUT when an attestation of the release
# workflow already verifies for the digest, so that a rerun creates no new
# one (FY-0027); attested=false otherwise.
# Inputs (environment): GH_TOKEN, REPOSITORY (owner/name), IMAGE (registry
# repository), DIGEST, PREDICATE (empty for provenance).
set -euo pipefail
args=(--repo "$REPOSITORY" --signer-workflow "$REPOSITORY/.github/workflows/release.yaml")
if [[ -n ${PREDICATE-} ]]; then
  args+=(--predicate-type "$PREDICATE")
fi
if gh attestation verify "oci://$IMAGE@$DIGEST" "${args[@]}" >/dev/null 2>&1; then
  echo "attested=true" >>"$GITHUB_OUTPUT"
else
  echo "attested=false" >>"$GITHUB_OUTPUT"
fi
