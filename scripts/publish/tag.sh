#!/usr/bin/env bash
# Usage: publish-tag REPOSITORY VERSION DIGEST
#
# Sets the release tag vVERSION at the manifest list DIGEST when the tag is
# absent (FY-0032). The list must be pushed and attested first, so that no tag
# points at a list without provenance. Fails when the tag points at another
# digest or its state cannot be read. The registry login must exist.
# Inputs (environment): PUBLISH_LIB, scripts/publish/lib.sh.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

# shellcheck source=/dev/null # scripts/publish/lib.sh, from the app
source "$PUBLISH_LIB"

repository=$1 version=$2 digest=$3
tag=v$version
require_version "$version"
require_digest "$digest"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

state=$(tag_state "$tag")
check_tag_immutable "$tag" "$state" "$digest"
if [[ $state == absent ]]; then
  crane tag "$repository@$digest" "$tag" >&2
  echo "$tag now points at $digest."
else
  echo "$tag already points at $digest."
fi
