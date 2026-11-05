# shellcheck shell=bash disable=SC2154 # repository and work come from the script
# Checks of the arguments and the release tag that the publish-* scripts
# share, sourced from $PUBLISH_LIB (FY-0032). tag_state and
# check_tag_immutable use $repository and $work of the script.

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

# check_tag_immutable TAG STATE DIGEST: exits when TAG, in STATE, is at
# another digest than DIGEST.
check_tag_immutable() {
  local tag=$1 state=$2 digest=$3
  [[ $state == absent || $state == "$digest" ]] && return 0
  echo "error: $repository:$tag points at $state, not at $digest; release tags are immutable" >&2
  exit 1
}
