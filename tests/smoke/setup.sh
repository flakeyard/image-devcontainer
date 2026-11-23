# shellcheck shell=bash disable=SC2016,SC2154 # commands run in the container; the variables come from lib.sh
# Smoke tests of devcontainer-setup (ADR-0002). Sourced by scripts/smoke.sh
# after tests/smoke/lib.sh. Inputs (environment): IMAGE, WORK.

# The owner of the workspaces here, which dev adopts.
setup_owner=1006:1006

# workspace NAME FIXTURE: copies FIXTURE of tests/fixture to WORK/setup-NAME
# and gives it to setup_owner; prints its path.
workspace() {
  local dir=${WORK}/setup-$1
  cp -R "${fixtures}/$2" "${dir}"
  sudo chown -R "${setup_owner}" "${dir}"
  echo "${dir}"
}

test_case "rejects arguments"
run -- sh -c 'devcontainer-setup now; echo "exit $?"'
expect_line "exit 2"
expect_text "usage: devcontainer-setup"

test_case "a working project passes, also in a worktree inside the workspace"
dir=$(workspace working project)
run -i -v "${dir}:/home/dev/project" -w /home/dev/project -- bash -s <"${probes}/setup-git.sh"
expect_line "workspace exit 0"
expect_line "inner exit 0"
expect_line "devcontainer-setup: /home/dev/project: shell loaded, pre-commit hook checked with 1 store paths"
expect_line "devcontainer-setup: /home/dev/project/.worktrees/inner: shell loaded, pre-commit hook checked with 1 store paths"

test_case "a project without git hooks passes with a notice"
dir=$(workspace plain project)
run -v "${dir}:/home/dev/project" -w /home/dev/project -- sh -c 'devcontainer-setup </dev/null; echo "exit $?"'
expect_line "exit 0"
expect_text "skipping the git hooks"
expect_line "devcontainer-setup: /home/dev/project: shell loaded, not a git repository, no hooks"

test_case "a broken shell fails, also after a working one"
dir=$(workspace broken broken-project)
run -v "${dir}:/home/dev/project" -w /home/dev/project -- sh -c 'devcontainer-setup </dev/null; echo "exit $?"'
expect_line "exit 1"
expect_text "devcontainer-setup: the shell of .envrc failed to load"
expect_no_text "shell loaded"
# The cache of nix-direnv holds the working shell, which it would fall back to.
dir=$(workspace broken-later project)
run -v "${dir}:/home/dev/project" -v "${fixtures}/broken-project:/broken:ro" -w /home/dev/project -- \
  sh -c 'devcontainer-setup </dev/null; echo "first exit $?"; cp /broken/flake.nix flake.nix; devcontainer-setup </dev/null; echo "second exit $?"'
expect_line "first exit 0"
expect_line "second exit 1"
expect_text "devcontainer-setup: the shell of .envrc failed to load"

test_case "a hook whose tool is missing from the store fails"
dir=$(workspace missing-tool project)
run -i -v "${dir}:/home/dev/project" -w /home/dev/project -- bash -s missing <"${probes}/setup-git.sh"
expect_line "workspace exit 1"
expect_text "store paths this store does not have: /nix/store/00000000000000000000000000000000-missing"

test_case "a worktree outside the workspace fails with the message"
# The layout of git worktree add: the git directory is on the host, outside
# the mount of the worktree.
dir=$(workspace outside project)
mkdir -p "${WORK}/setup-main/.git/worktrees/outside"
printf 'gitdir: %s\n' "${WORK}/setup-main/.git/worktrees/outside" | sudo tee "${dir}/.git" >/dev/null
run -v "${dir}:/home/dev/project" -w /home/dev/project -- sh -c 'devcontainer-setup </dev/null; echo "exit $?"'
expect_line "exit 1"
expect_text "create worktrees inside the workspace, e.g. git worktree add .worktrees/<name>"
expect_no_text "direnv: loading"
