# shellcheck shell=bash
# Tests of scripts/check/release-rebuild.sh, with stubs of nix and crane, a git
# repository and a registry in a directory.
# shellcheck disable=SC2154 # work and registry come from setup

# rebuild NAME EXPECTED [ARCH [DIR]]: test NAME runs check-release-rebuild for
# ARCH, amd64 by default, in DIR, the repository of the test by default;
# EXPECTED is ok or fail.
rebuild() {
  local name=$1 expected=$2 arch=${3:-amd64} dir=${4:-$work/repo}
  pushd "$dir" >/dev/null || return
  run "release-rebuild: $name" "$expected" scripts/check/release-rebuild.sh -- ghcr.io/x/y "$arch"
  popd >/dev/null || return
}

# rebuild_setup: a git repository with the tag v1.0.0 and a registry that
# publishes it with the platform digests of the stub.
rebuild_setup() {
  stubbed_setup
  # Independent of the git configuration of whoever runs the tests.
  local -x GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  local digest index
  digest=$(digest_of a)
  apply TARBALL_DIGEST="$digest"
  mkdir "$work/repo"
  git -C "$work/repo" init -q
  git -C "$work/repo" -c commit.gpgsign=false commit -q --allow-empty -m init
  git -C "$work/repo" -c tag.gpgsign=false tag v1.0.0
  index=$(printf '{"manifests":[{"digest":"%s","platform":{"architecture":"amd64"}}]}' "$digest")
  printf '%s' "$index" >"$registry/manifests/sha256:index"
  echo sha256:index >"$registry/tags/v1.0.0"
}

rebuild_setup
rebuild "the rebuild has the published digest" ok
expect message "v1.0.0 rebuilt for amd64 has the published digest"
finish

rebuild_setup
apply TARBALL_DIGEST="$(digest_of b)"
rebuild "another digest fails" fail
expect message "the registry has sha256:aaaa"
finish

rebuild_setup
git -C "$work/repo" tag -d v1.0.0 >/dev/null
rebuild "nothing to do before the first release" ok
expect message "No release"
finish

rebuild_setup
rm -r "$registry/tags"
rebuild "a release missing from the registry fails" fail
expect message "::error::The release v1.0.0 was never published"
expect message "make a new patch release"
finish

rebuild_setup
git -C "$work/repo" -c tag.gpgsign=false tag v1.1.0
rebuild "the newest tag is the release" fail
expect message "The release v1.1.0 was never published"
finish

rebuild_setup
git -C "$work/repo" tag -d v1.0.0 >/dev/null
git -C "$work/repo" -c tag.gpgsign=false tag v1.0.0-rc.1
git -C "$work/repo" -c tag.gpgsign=false tag v1.0
rebuild "other tags are no releases" ok
expect message "No release"
finish

rebuild_setup
mkdir "$work/plain"
# git must not find a repository above the directory.
apply GIT_CEILING_DIRECTORIES="$work"
rebuild "git errors fail" fail amd64 "$work/plain"
expect message "not a git repository"
finish

rebuild_setup
rebuild "no image of the architecture fails" fail arm64
expect message "has no arm64 image"
finish

rebuild_setup
apply CRANE_MANIFEST_DENIED=1
rebuild "registry errors fail" fail
expect message "DENIED"
finish

rebuild_setup
rebuild "uses the tools of the release" ok
expect call "/source#publish-digest -- "
finish

# worktrees: the number of worktrees of the repository of the test, besides
# its own.
worktrees() { git -C "$work/repo" worktree list --porcelain | grep -c '^worktree ' | awk '{ print $1 - 1 }'; }

rebuild_setup
rebuild "removes the worktree of the release" ok
if [[ -n $current ]] && [[ $(worktrees) != 0 ]]; then report "worktrees left: $(git -C "$work/repo" worktree list)"; fi
finish

rebuild_setup
apply RUN_ERROR="error: build failed"
rebuild "a failing rebuild leaves no worktree" fail
expect message "build failed"
if [[ -n $current ]] && [[ $(worktrees) != 0 ]]; then report "worktrees left: $(git -C "$work/repo" worktree list)"; fi
finish
