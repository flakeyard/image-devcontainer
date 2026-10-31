#!/usr/bin/env bash
# Usage: check-release-rebuild REPOSITORY ARCH
#
# Rebuilds the newest release from its git tag and compares the platform
# digest of ARCH with the one published in REPOSITORY (FY-0027). Run in a full
# clone with tags; passes with a notice before the first release.
set -euo pipefail
shopt -s inherit_errexit

repository=$1 arch=$2
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# The newest release is the newest tag vX.Y.Z of the repository; its image
# must be in the registry.
newest=$(git tag -l 'v*.*.*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)
if [[ -z $newest ]]; then
  echo "::notice::No release yet; nothing to rebuild."
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
