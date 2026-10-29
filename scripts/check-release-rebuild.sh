#!/usr/bin/env bash
# Usage: check-release-rebuild REPOSITORY ARCH
#
# Rebuilds the newest release in the registry from its git tag and compares
# the platform digest of ARCH with the published one (FY-0027). Run in a
# full clone with tags; passes with a notice before the first release.
set -euo pipefail
shopt -s inherit_errexit

repository=$1 arch=$2
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# Before the first push, the registry does not know the repository.
if ! tags=$(crane ls "$repository" 2>"$work/errors"); then
  if grep -q NAME_UNKNOWN "$work/errors"; then
    tags=""
  else
    cat "$work/errors" >&2
    exit 1
  fi
fi
newest=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" | sort -V | tail -n 1 || true)
if [[ -z $newest ]]; then
  echo "::notice::No release in $repository yet; nothing to rebuild."
  exit 0
fi
published=$(crane manifest "$repository:$newest" |
  jq -r --arg arch "$arch" '.manifests[] | select(.platform.architecture == $arch) | .digest')

git worktree add --detach "$work/source" "$newest" >/dev/null
# The tools of the release, not of HEAD: another crane may compress differently.
rebuilt=$(nix run --no-update-lock-file "$work/source#platform-digest" -- "$work/image.tar" "$work/source")
git worktree remove --force "$work/source"

if [[ $rebuilt != "$published" ]]; then
  echo "::error::$newest rebuilt for $arch has digest $rebuilt, the registry has $published."
  exit 1
fi
echo "$newest rebuilt for $arch has the published digest $published."
