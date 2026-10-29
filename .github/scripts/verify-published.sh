#!/usr/bin/env bash
# Pulls the published manifest list on this runner and checks it (FY-0027):
# the platform of this runner has the tested digest, the image runs, and the
# list and the platform have attestations of the release workflow.
# Inputs (environment): GH_TOKEN, REPOSITORY, IMAGE, INDEX, PLATFORM (the
# tested digest of this runner's platform).
set -euo pipefail
reference=$IMAGE@$INDEX
docker pull --quiet "$reference" >/dev/null
arch=$(docker version --format '{{.Server.Arch}}')
listed=$(docker buildx imagetools inspect --raw "$reference" |
  jq -r --arg arch "$arch" '.manifests[] | select(.platform.architecture == $arch) | .digest')
if [[ $listed != "$PLATFORM" ]]; then
  echo "error: the list names $listed for $arch, $PLATFORM was tested" >&2
  exit 1
fi
docker run --rm "$reference" nix --version
args=(--repo "$REPOSITORY" --signer-workflow "$REPOSITORY/.github/workflows/release.yaml")
gh attestation verify "oci://$reference" "${args[@]}" >/dev/null
gh attestation verify "oci://$IMAGE@$PLATFORM" "${args[@]}" >/dev/null
gh attestation verify "oci://$IMAGE@$PLATFORM" "${args[@]}" \
  --predicate-type https://cyclonedx.org/bom >/dev/null
echo "Verified $reference and $PLATFORM with their attestations."
