#!/usr/bin/env bash
# Usage: publish-index REPOSITORY VERSION REVISION AMD64_DIGEST ARM64_DIGEST
#
# Publishes the manifest list of a release (FY-0027): writes it as canonical
# JSON with the version and commit as annotations, pushes it by its digest,
# then sets the tag vVERSION when it is absent. Fails when the tag points at
# another digest or its state cannot be read. Prints the digest of the list.
# The registry login must exist.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

index_type=application/vnd.oci.image.index.v1+json
docker_manifest_type=application/vnd.docker.distribution.manifest.v2+json
oci_manifest_type=application/vnd.oci.image.manifest.v1+json
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+$'
digest_pattern='^sha256:[0-9a-f]{64}$'

# require_version VERSION: exits unless VERSION is X.Y.Z.
require_version() {
  local version=$1
  [[ $version =~ $version_pattern ]] && return 0
  echo "error: '$version' is not a version" >&2
  exit 2
}

# require_digest DIGEST: exits unless DIGEST is a sha256 digest.
require_digest() {
  local digest=$1
  [[ $digest =~ $digest_pattern ]] && return 0
  echo "error: '$digest' is not a digest" >&2
  exit 2
}

# descriptor DIGEST ARCH: the entry of a platform manifest, which must exist
# in the registry. Keeps the manifest in $work, which the script removes.
descriptor() {
  local digest=$1 arch=$2 manifest=$work/$2.json type size
  # The exact bytes: $(...) would drop trailing newlines and change the size.
  crane manifest "$repository@$digest" >"$manifest"
  size=$(wc -c <"$manifest")
  type=$(jq -r .mediaType "$manifest")
  case $type in
    "$docker_manifest_type" | "$oci_manifest_type") ;;
    *)
      echo "error: $repository@$digest is not an image manifest: $type" >&2
      exit 1
      ;;
  esac
  jq -cn --arg digest "$digest" --arg arch "$arch" --arg type "$type" --argjson size "$size" \
    '{mediaType: $type, digest: $digest, size: $size, platform: {architecture: $arch, os: "linux"}}'
}

# index_manifest AMD64_ENTRY ARM64_ENTRY: the manifest list as canonical JSON,
# with the version and the revision as annotations.
index_manifest() {
  local amd64_entry=$1 arm64_entry=$2
  jq -cnS \
    --argjson amd64 "$amd64_entry" \
    --argjson arm64 "$arm64_entry" \
    --arg type "$index_type" --arg version "$version" --arg revision "$revision" \
    '{schemaVersion: 2, mediaType: $type,
      manifests: [$amd64, $arm64],
      annotations: {
        "org.opencontainers.image.description": "Dev container image with multi-user Nix, direnv and nix-direnv",
        "org.opencontainers.image.licenses": "MIT",
        "org.opencontainers.image.revision": $revision,
        "org.opencontainers.image.source": "https://github.com/flakeyard/image-devcontainer",
        "org.opencontainers.image.version": $version}}'
}

# content_digest CONTENT: the digest of the bytes of CONTENT.
content_digest() {
  local content=$1 sum
  sum=$(printf '%s' "$content" | sha256sum)
  echo "sha256:${sum%% *}"
}

# tag_state TAG: the digest TAG points at, or "absent" when the registry
# says it does not know TAG. Exits on any other error.
tag_state() {
  local tag=$1 current
  if current=$(crane digest "$repository:$tag" 2>"$work/errors"); then
    echo "$current"
  elif grep -q MANIFEST_UNKNOWN "$work/errors"; then
    echo absent
  else
    echo "error: cannot read $repository:$tag: $(cat "$work/errors")" >&2
    exit 1
  fi
}

# check_tag_immutable STATE DIGEST: exits when the tag is at another digest.
check_tag_immutable() {
  local state=$1 digest=$2
  [[ $state == absent || $state == "$digest" ]] && return 0
  echo "error: $repository:$tag points at $state, not at $digest; release tags are immutable" >&2
  exit 1
}

repository=$1 version=$2 revision=$3 amd64=$4 arm64=$5
tag=v$version
require_version "$version"
require_digest "$amd64"
require_digest "$arm64"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# The list as canonical JSON and its digest. Assigned first: a failure
# inside an argument would not stop the script.
amd64_entry=$(descriptor "$amd64" amd64)
arm64_entry=$(descriptor "$arm64" arm64)
index=$(index_manifest "$amd64_entry" "$arm64_entry")
digest=$(content_digest "$index")

# The tag may only be set when absent or already at the digest.
state=$(tag_state "$tag")
check_tag_immutable "$state" "$digest"

# The list is pushed by its digest before the tag points at it.
printf '%s' "$index" | regctl manifest put --content-type "$index_type" "$repository@$digest" >&2
if [[ $state == absent ]]; then
  crane tag "$repository@$digest" "$tag" >&2
fi
echo "$digest"
