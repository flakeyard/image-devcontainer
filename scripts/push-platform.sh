#!/usr/bin/env bash
# Usage: push-platform REPOSITORY TESTED_DIGEST [FLAKE]
#
# Builds the image of this system again, fails unless its digest is the
# tested one, and pushes it by digest, without a tag (FY-0027). Prints the
# digest. The registry login must exist.
# Inputs (environment): PLATFORM_DIGEST, the platform-digest app, which
# computed the tested digest.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

repository=$1
tested=$2
flake=${3:-.}
digest_pattern='^sha256:[0-9a-f]{64}$'
[[ $tested =~ $digest_pattern ]] || {
  echo "error: '$tested' is not a digest" >&2
  exit 2
}

archive=$(mktemp)
trap 'rm -f -- "$archive"' EXIT
# The tested and the pushed digest come from the same code.
digest=$("$PLATFORM_DIGEST" "$archive" "$flake")
if [[ $digest != "$tested" ]]; then
  echo "error: the image has digest $digest, but $tested was tested" >&2
  exit 1
fi
crane push "$archive" "$repository@$digest" >&2
echo "$digest"
