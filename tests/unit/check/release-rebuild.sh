#!/usr/bin/env bash
# Unit tests of scripts/check/release-rebuild.sh, with stubs of nix and crane,
# a git repository and a registry in a directory. Inputs (environment):
# SCRIPTS, the scripts directory; STUBS, the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# rebuild [ARCH [DIR]]: runs check-release-rebuild for ARCH, amd64 by
# default, in DIR, the repository of the test by default.
rebuild() {
  local arch=${1:-amd64} dir=${2:-$work/repo}
  (cd "$dir" && "$SCRIPTS/check/release-rebuild.sh" ghcr.io/x/y "$arch")
}

# setup: a git repository with the tag v1.0.0 and a registry that publishes
# it with the platform digests of the stub.
setup() {
  work=$(mktemp -d)
  TARBALL_DIGEST=sha256:$(printf 'a%.0s' {1..64})
  export CALLS=$work/calls REGISTRY=$work/registry SYSTEM=x86_64-linux TARBALL_DIGEST
  export PATH=$STUBS:$PATH
  : >"$CALLS"
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags" "$work/repo"
  git -C "$work/repo" init -q
  # Independent of the git configuration of whoever runs the tests.
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git -C "$work/repo" -c commit.gpgsign=false commit -q --allow-empty -m init
  git -C "$work/repo" -c tag.gpgsign=false tag v1.0.0
  index=$(printf '{"manifests":[{"digest":"%s","platform":{"architecture":"amd64"}}]}' "$TARBALL_DIGEST")
  printf '%s' "$index" >"$REGISTRY/manifests/sha256:index"
  echo sha256:index >"$REGISTRY/tags/v1.0.0"
}

setup
run "release-rebuild: the rebuild has the published digest" ok rebuild
expect message "v1.0.0 rebuilt for amd64 has the published digest"
finish

setup
TARBALL_DIGEST=sha256:$(printf 'b%.0s' {1..64})
run "release-rebuild: another digest fails" fail rebuild
expect message "the registry has sha256:aaaa"
finish

setup
git -C "$work/repo" tag -d v1.0.0 >/dev/null
run "release-rebuild: nothing to do before the first release" ok rebuild
expect message "No release"
finish

setup
rm -r "$REGISTRY/tags"
run "release-rebuild: a release missing from the registry fails" fail rebuild
expect message "::error::The release v1.0.0 was never published"
expect message "make a new patch release"
finish

setup
git -C "$work/repo" -c tag.gpgsign=false tag v1.1.0
run "release-rebuild: the newest tag is the release" fail rebuild
expect message "The release v1.1.0 was never published"
finish

setup
git -C "$work/repo" tag -d v1.0.0 >/dev/null
git -C "$work/repo" -c tag.gpgsign=false tag v1.0.0-rc.1
git -C "$work/repo" -c tag.gpgsign=false tag v1.0
run "release-rebuild: other tags are no releases" ok rebuild
expect message "No release"
finish

setup
mkdir "$work/plain"
# git must not find a repository above the directory.
GIT_CEILING_DIRECTORIES=$work run "release-rebuild: git errors fail" fail rebuild amd64 "$work/plain"
expect message "not a git repository"
finish

setup
run "release-rebuild: no image of the architecture fails" fail rebuild arm64
expect message "has no arm64 image"
finish

setup
export CRANE_MANIFEST_DENIED=1
run "release-rebuild: registry errors fail" fail rebuild
expect message "DENIED"
unset CRANE_MANIFEST_DENIED
finish

setup
run "release-rebuild: uses the tools of the release" ok rebuild
expect called "/source#publish-digest -- "
finish

setup
APPS='["platform-digest","smoke"]' run "release-rebuild: a release before the rename has platform-digest" ok rebuild
expect called "/source#platform-digest -- "
finish

summary
