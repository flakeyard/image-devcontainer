#!/usr/bin/env bash
# Usage: publish-major REPOSITORY MAJOR
#
# Points vMAJOR at the manifest list of the newest vMAJOR.Y.Z in the registry
# (FY-0027). It never moves back, because the newest existing release is
# always at least the one vMAJOR points at. The registry login must exist.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

repository=$1 major=$2
[[ $major =~ ^[0-9]+$ ]] || {
  echo "error: '$major' is not a major version" >&2
  exit 2
}

tags=$(crane ls "$repository")
newest=$(grep -E "^v$major\.[0-9]+\.[0-9]+$" <<<"$tags" | sort -V | tail -n 1 || true)
if [[ -z $newest ]]; then
  echo "error: no release of major version $major in $repository" >&2
  exit 1
fi
digest=$(crane digest "$repository:$newest")
current=$(crane digest "$repository:v$major" 2>/dev/null || true)
if [[ $current == "$digest" ]]; then
  echo "v$major already points at $newest."
  exit 0
fi
crane tag "$repository@$digest" "v$major" >&2
echo "v$major now points at $newest."
