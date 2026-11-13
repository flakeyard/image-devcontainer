#!/usr/bin/env bash
# Usage: publish-verify REPOSITORY IMAGE INDEX VERSION REVISION ARCH
#
# Checks the published image of a release on a runner of ARCH (FY-0032):
#   - the git tag vVERSION is at REVISION;
#   - vVERSION points at the manifest list INDEX, which has exactly the two
#     platforms, the version and the commit as annotations, and the tested
#     digest for ARCH;
#   - the image pulled by INDEX runs;
#   - the list has provenance from the release workflow at the commit of the
#     git tag, which only an approved release creates;
#   - the platform has provenance and an SBOM from the release workflow. They
#     are not bound to the commit: a platform digest keeps the attestations of
#     the release that first published it.
# Inputs (environment): GH_TOKEN; TESTED_AMD64 and TESTED_ARM64, the tested
# digests; PUBLISH_LIB, scripts/publish/lib.sh;
# SHELL_LIB, the directory of the shell library. Needs docker, as on
# GitHub-hosted runners.
set -euo pipefail
shopt -s inherit_errexit

repository=$1 image=$2 index=$3 version=$4 revision=$5 arch=$6
readonly sbom=https://cyclonedx.org/bom
# shellcheck source=/dev/null # scripts/publish/lib.sh, from the app
source "$PUBLISH_LIB"
platform=$(tested_digest "$arch")
# shellcheck source=/dev/null # github/api.sh of the library, from the app
source "$SHELL_LIB/github/api.sh"

# The commit of the git tag vVERSION, from the API.
tag_commit() {
  api_get "repos/$repository/commits/tags/v$version" | jq -r .sha
}

check_git_tag() {
  local commit
  commit=$(tag_commit) || fail "cannot read the git tag v$version"
  [[ $commit == "$revision" ]] || fail "the git tag v$version is at $commit, not at $revision"
}

check_tag() {
  local tagged
  tagged=$(crane digest "$image:v$version")
  [[ $tagged == "$index" ]] || fail "$image:v$version points at $tagged, not at $index"
}

# check_list LIST: the platforms, the annotations and the tested digest.
check_list() {
  local list=$1 listed
  jq -e '[.manifests[].platform.architecture] | sort == ["amd64", "arm64"]' <<<"$list" >/dev/null \
    || fail "the list does not have exactly amd64 and arm64: $list"
  jq -e --arg v "$version" --arg r "$revision" '
    .annotations["org.opencontainers.image.version"] == $v
      and .annotations["org.opencontainers.image.revision"] == $r' <<<"$list" >/dev/null \
    || fail "the annotations of the list are not $version and $revision"
  listed=$(jq -r --arg arch "$arch" '.manifests[] | select(.platform.architecture == $arch) | .digest' <<<"$list")
  [[ $listed == "$platform" ]] || fail "the list names $listed for $arch, $platform was tested"
}

check_runs() {
  docker pull --quiet "$image@$index" >/dev/null
  docker run --rm "$image@$index" nix --version
}

check_git_tag
check_tag
list=$(crane manifest "$image@$index")
check_list "$list"
check_runs
verify_attestation "$repository" "$image" "$index" --source-digest "$revision"
verify_attestation "$repository" "$image" "$platform"
verify_attestation "$repository" "$image" "$platform" --predicate-type "$sbom"
echo "Verified $image:v$version@$index on $arch with its attestations."
