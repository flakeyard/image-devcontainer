#!/usr/bin/env bash
# Usage: check-release-rebuild REPOSITORY ARCH
#
# Rebuilds the newest release in the registry from its git tag and compares
# the platform digest of ARCH with the published one (FY-0027). Run in a
# full clone with tags; passes with a notice before the first release.
set -euo pipefail
shopt -s inherit_errexit

repository=$1 arch=$2
tags=$(crane ls "$repository")
newest=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" | sort -V | tail -n 1 || true)
if [[ -z $newest ]]; then
  echo "::notice::No release in $repository yet; nothing to rebuild."
  exit 0
fi
published=$(crane manifest "$repository:$newest" |
  jq -r --arg arch "$arch" '.manifests[] | select(.platform.architecture == $arch) | .digest')

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
git worktree add --detach "$work/source" "$newest" >/dev/null
stream=$(nix build --no-link --no-update-lock-file --print-out-paths "$work/source#image")
"$stream" >"$work/image.tar"
rebuilt=$(crane digest --tarball "$work/image.tar")
git worktree remove --force "$work/source"

if [[ $rebuilt != "$published" ]]; then
  echo "::error::$newest rebuilt for $arch has digest $rebuilt, the registry has $published."
  exit 1
fi
echo "$newest rebuilt for $arch has the published digest $published."
