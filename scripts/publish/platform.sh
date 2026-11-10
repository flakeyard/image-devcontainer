#!/usr/bin/env bash
# Usage: publish-platform REPOSITORY TESTED_DIGEST [FLAKE]
#
# Builds the image of this system again, fails unless its digest is the
# tested one, and pushes it by digest, without a tag (FY-0032). Prints the
# digest. The registry login must exist.
# Inputs (environment): PUBLISH_DIGEST, the publish-digest app, which
# computed the tested digest; PUBLISH_LIB, scripts/publish/lib.sh.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

repository=$1
tested=$2
flake=${3:-.}
# shellcheck source=/dev/null # scripts/publish/lib.sh, from the app
source "$PUBLISH_LIB"
require_digest "$tested"

archive=$(mktemp)
trap 'rm -f -- "$archive"' EXIT
# The tested and the pushed digest come from the same code.
digest=$("$PUBLISH_DIGEST" "$archive" "$flake")
if [[ $digest != "$tested" ]]; then
  fail "the image has digest $digest, but $tested was tested"
fi
crane push "$archive" "$repository@$digest" >&2
echo "$digest"
