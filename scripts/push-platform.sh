#!/usr/bin/env bash
# Usage: push-platform REPOSITORY TESTED_DIGEST [FLAKE]
#
# Builds the image of this system again, fails unless its digest is the
# tested one, and pushes it by digest, without a tag (FY-0027). Prints the
# digest. The registry login must exist.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

repository=$1
tested=$2
flake=${3:-.}
[[ $tested =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "error: '$tested' is not a digest" >&2
  exit 2
}

archive=$(mktemp)
trap 'rm -f -- "$archive"' EXIT
stream=$(nix build --no-link --no-update-lock-file --print-out-paths "$flake#image")
"$stream" >"$archive"
digest=$(crane digest --tarball "$archive")
if [[ $digest != "$tested" ]]; then
  echo "error: the image has digest $digest, but $tested was tested" >&2
  exit 1
fi
crane push "$archive" "$repository@$digest" >&2
echo "$digest"
