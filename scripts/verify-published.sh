#!/usr/bin/env bash
# Usage: verify-published REPOSITORY IMAGE INDEX VERSION REVISION ARCH PLATFORM
#
# Checks the published image of a release on a runner of ARCH (FY-0027):
#   - vVERSION points at the manifest list INDEX, which has exactly the two
#     platforms, the version and the commit as annotations, and PLATFORM, the
#     tested digest, for ARCH;
#   - the image pulled by INDEX runs;
#   - the list and the platform have provenance, and the platform an SBOM,
#     from the release workflow. They are not bound to the commit: a platform
#     digest keeps the attestations of the release that first published it,
#     and the annotations of the attested list name the commit.
# Inputs (environment): GH_TOKEN. Needs docker, as on GitHub-hosted runners.
set -euo pipefail
shopt -s inherit_errexit

repository=$1 image=$2 index=$3 version=$4 revision=$5 arch=$6 platform=$7
fail() {
  echo "error: $1" >&2
  exit 1
}

tagged=$(crane digest "$image:v$version")
[[ $tagged == "$index" ]] || fail "$image:v$version points at $tagged, not at $index"
list=$(crane manifest "$image@$index")
jq -e '[.manifests[].platform.architecture] | sort == ["amd64", "arm64"]' <<<"$list" >/dev/null ||
  fail "the list does not have exactly amd64 and arm64: $list"
jq -e --arg v "$version" --arg r "$revision" \
  '.annotations["org.opencontainers.image.version"] == $v and .annotations["org.opencontainers.image.revision"] == $r' \
  <<<"$list" >/dev/null || fail "the annotations of the list are not $version and $revision"
listed=$(jq -r --arg arch "$arch" '.manifests[] | select(.platform.architecture == $arch) | .digest' <<<"$list")
[[ $listed == "$platform" ]] || fail "the list names $listed for $arch, $platform was tested"

docker pull --quiet "$image@$index" >/dev/null
docker run --rm "$image@$index" nix --version

args=(--repo "$repository" --signer-workflow "$repository/.github/workflows/release.yaml"
  --deny-self-hosted-runners)
gh attestation verify "oci://$image@$index" "${args[@]}" >/dev/null
gh attestation verify "oci://$image@$platform" "${args[@]}" >/dev/null
gh attestation verify "oci://$image@$platform" "${args[@]}" --predicate-type https://cyclonedx.org/bom >/dev/null
echo "Verified $image:v$version@$index on $arch with its attestations."
