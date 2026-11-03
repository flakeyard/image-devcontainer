#!/usr/bin/env bash
# Usage: publish-tag REPOSITORY VERSION DIGEST
#
# Sets the release tag vVERSION at the manifest list DIGEST when the tag is
# absent (FY-0027). The list must be pushed and attested first, so that no tag
# points at a list without provenance. Fails when the tag points at another
# digest or its state cannot be read. The registry login must exist.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

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

# check_tag_immutable STATE: exits when the tag is at another digest.
check_tag_immutable() {
  local state=$1
  [[ $state == absent || $state == "$digest" ]] && return 0
  echo "error: $repository:$tag points at $state, not at $digest; release tags are immutable" >&2
  exit 1
}

repository=$1 version=$2 digest=$3
tag=v$version
require_version "$version"
require_digest "$digest"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

state=$(tag_state "$tag")
check_tag_immutable "$state"
if [[ $state == absent ]]; then
  crane tag "$repository@$digest" "$tag" >&2
  echo "$tag now points at $digest."
else
  echo "$tag already points at $digest."
fi
