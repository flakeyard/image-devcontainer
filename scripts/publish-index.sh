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

repository=$1 version=$2 revision=$3 amd64=$4 arm64=$5
tag=v$version
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: '$version' is not a version" >&2
  exit 2
}
for digest in "$amd64" "$arm64"; do
  [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "error: '$digest' is not a digest" >&2
    exit 2
  }
done

# descriptor DIGEST ARCHITECTURE: the entry of a platform manifest, which
# must exist in the registry.
descriptor() {
  local file type size
  file=$(mktemp)
  # The exact bytes: $(...) would drop trailing newlines and change the size.
  crane manifest "$repository@$1" >"$file" || return 1
  size=$(wc -c <"$file")
  type=$(jq -r .mediaType "$file")
  rm -f -- "$file"
  case $type in
    application/vnd.docker.distribution.manifest.v2+json | application/vnd.oci.image.manifest.v1+json) ;;
    *)
      echo "error: $repository@$1 is not an image manifest: $type" >&2
      return 1
      ;;
  esac
  jq -cn --arg digest "$1" --arg arch "$2" --arg type "$type" --argjson size "$size" \
    '{mediaType: $type, digest: $digest, size: $size, platform: {architecture: $arch, os: "linux"}}'
}

# Assigned first: a failure inside an argument would not stop the script.
amd64_entry=$(descriptor "$amd64" amd64)
arm64_entry=$(descriptor "$arm64" arm64)
index=$(jq -cnS \
  --argjson amd64 "$amd64_entry" \
  --argjson arm64 "$arm64_entry" \
  --arg version "$version" --arg revision "$revision" \
  '{schemaVersion: 2, mediaType: "application/vnd.oci.image.index.v1+json",
    manifests: [$amd64, $arm64],
    annotations: {
      "org.opencontainers.image.description": "Dev container image with multi-user Nix, direnv and nix-direnv",
      "org.opencontainers.image.licenses": "MIT",
      "org.opencontainers.image.revision": $revision,
      "org.opencontainers.image.source": "https://github.com/flakeyard/image-devcontainer",
      "org.opencontainers.image.version": $version}}')
digest=sha256:$(printf '%s' "$index" | sha256sum | cut -d' ' -f1)

# The tag is absent only when the registry says so.
errors=$(mktemp)
trap 'rm -f -- "$errors"' EXIT
if current=$(crane digest "$repository:$tag" 2>"$errors"); then
  state=$current
elif grep -q MANIFEST_UNKNOWN "$errors"; then
  state=absent
else
  echo "error: cannot read $repository:$tag: $(cat "$errors")" >&2
  exit 1
fi
if [[ $state != absent && $state != "$digest" ]]; then
  echo "error: $repository:$tag points at $state, not at $digest; release tags are immutable" >&2
  exit 1
fi

printf '%s' "$index" | regctl manifest put \
  --content-type application/vnd.oci.image.index.v1+json "$repository@$digest" >&2
if [[ $state == absent ]]; then
  crane tag "$repository@$digest" "$tag" >&2
fi
echo "$digest"
