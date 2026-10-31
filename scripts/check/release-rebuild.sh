#!/usr/bin/env bash
# Usage: check-release-rebuild REPOSITORY ARCH
#
# Rebuilds the newest release from its git tag and compares the platform
# digest of ARCH with the one published in REPOSITORY (FY-0027). Run in a full
# clone with tags; passes with a notice before the first release.
set -euo pipefail
shopt -s inherit_errexit

repository=$1 arch=$2
release_pattern='^v[0-9]+\.[0-9]+\.[0-9]+$'
# The app that computes the platform digest, and its name in releases made
# before it was renamed.
digest_app=publish-digest
old_digest_app=platform-digest
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# newest_release: the newest tag vX.Y.Z of the repository, nothing when there
# is none. Its image must be in the registry.
newest_release() {
  local tags
  tags=$(git tag -l 'v*.*.*')
  # grep exits with 1 when no tag is a release, with more on errors.
  { grep -E -- "$release_pattern" <<<"$tags" || (($? == 1)); } | sort -V | tail -n 1
}

# never_published RELEASE: fails with what to do about a release whose image
# is not in the registry. The runner reads workflow commands on stderr too.
never_published() {
  local release=$1
  echo "::error::The release $release was never published: $repository has no tag $release." \
    "Rerun the failed jobs of its release workflow, or after 30 days make a new patch release (FY-0027)." >&2
  exit 1
}

# published_digest RELEASE: the platform digest of ARCH that the registry has
# for RELEASE.
published_digest() {
  local release=$1 index digest
  if ! index=$(crane manifest "$repository:$release" 2>"$work/errors"); then
    cat -- "$work/errors" >&2
    # An unknown tag, or a repository that was never pushed to.
    if grep -qE 'MANIFEST_UNKNOWN|NAME_UNKNOWN' "$work/errors"; then
      never_published "$release"
    fi
    exit 1
  fi
  digest=$(jq -r --arg arch "$arch" '.manifests[] | select(.platform.architecture == $arch) | .digest' <<<"$index")
  if [[ -z $digest ]]; then
    echo "::error::The manifest list of $release in $repository has no $arch image." >&2
    exit 1
  fi
  echo "$digest"
}

# release_digest_app SOURCE: the app of the release in SOURCE that computes
# its platform digest.
release_digest_app() {
  local source=$1 system apps
  system=$(nix eval --raw --impure --expr builtins.currentSystem)
  apps=$(nix eval --no-update-lock-file --json "$source#apps.$system" --apply builtins.attrNames)
  if jq -e --arg app "$digest_app" 'any(.[]; . == $app)' <<<"$apps" >/dev/null; then
    echo "$digest_app"
  else
    echo "$old_digest_app"
  fi
}

newest=$(newest_release)
if [[ -z $newest ]]; then
  echo "::notice::No release yet; nothing to rebuild."
  exit 0
fi
published=$(published_digest "$newest")

git worktree add --detach "$work/source" "$newest" >/dev/null
# The tools of the release, not of HEAD: another crane may compress differently.
app=$(release_digest_app "$work/source")
rebuilt=$(nix run --no-update-lock-file "$work/source#$app" -- "$work/image.tar" "$work/source")
git worktree remove --force "$work/source"

if [[ $rebuilt != "$published" ]]; then
  echo "::error::$newest rebuilt for $arch has digest $rebuilt, the registry has $published."
  exit 1
fi
echo "$newest rebuilt for $arch has the published digest $published."
