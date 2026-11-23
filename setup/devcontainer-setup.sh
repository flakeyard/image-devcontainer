# shellcheck shell=bash
# Usage: devcontainer-setup
#
# Sets up the workspace in its working directory, as the postCreateCommand of
# a devcontainer.json (ADR-0002): refuses a worktree whose git directory is
# outside the mount of the workspace, makes git write relative paths for new
# worktrees, runs direnv allow, loads the shell
# strictly, checks the pre-commit hook and the store paths it names, and
# prints one summary line. Exits 1 at the first step that fails, and 2 when
# given arguments. writeShellApplication (nix/image/parts/devcontainer-setup.nix)
# adds the shebang, errexit, nounset and pipefail.

name=devcontainer-setup
# A store path, as the hooks of git-hooks.nix and their configuration name it.
store_path='/nix/store/[0-9a-z]{32}-[0-9A-Za-z+._?=-]+'
# The variables of a loaded environment: with them, direnv export evaluates
# nothing when it thinks the environment is current.
loaded_env=(DIRENV_DIR DIRENV_FILE DIRENV_DIFF DIRENV_WATCHES)

fail() {
  printf '%s: %s\n' "${name}" "$1" >&2
  exit 1
}

notice() { printf '%s: %s\n' "${name}" "$1" >&2; }

# check_worktree WORKSPACE: a .git file names a git directory that exists
# inside the mount that holds WORKSPACE, which worktrees inside it share.
check_worktree() {
  local workspace=$1 line gitdir mount
  [[ -f .git ]] || return 0
  IFS= read -r line <.git || true
  [[ ${line} == "gitdir: "* ]] || fail ".git is a file without a gitdir line"
  gitdir=${line#gitdir: }
  [[ ${gitdir} == /* ]] || gitdir=${workspace}/${gitdir}
  mount=$(findmnt --noheadings --output TARGET --target "${workspace}")
  if [[ -d ${gitdir} ]]; then
    gitdir=$(realpath -- "${gitdir}")
    [[ ${mount} == / || ${gitdir} == "${mount}"/* ]] && return 0
  fi
  fail "the git directory ${gitdir} of this worktree is outside ${mount} or does not exist; create worktrees inside the workspace, e.g. git worktree add .worktrees/<name>"
}

# relative_worktrees: in a git repository, git worktree add writes relative
# paths from now on, which hold both in the container and on the host, where
# the workspace has another path (git 2.48 or newer).
relative_worktrees() {
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  git config --local worktree.useRelativePaths true || fail "cannot set worktree.useRelativePaths"
}

# load_shell: loads the shell of .envrc as a new one, with errexit, nounset
# and pipefail in .envrc, and without the fallback of nix-direnv to a previous
# environment; with the configuration of the user, direnv ignores the exit
# status of .envrc. Its log goes to stderr.
load_shell() {
  local config status=0 env
  config=$(mktemp -d)
  printf '[global]\nstrict_env = true\n' >"${config}/direnv.toml"
  # The direnvrc of the user, which loads nix-direnv in the image.
  cat >"${config}/direnvrc" <<EOF
user_direnvrc=\${XDG_CONFIG_HOME:-\$HOME/.config}/direnv/direnvrc
if [[ -f \$user_direnvrc ]]; then
  source "\$user_direnvrc"
fi
if declare -F nix_direnv_disallow_fallback >/dev/null; then
  nix_direnv_disallow_fallback
fi
EOF
  env=$(env "${loaded_env[@]/#/-u}" DIRENV_CONFIG="${config}" direnv export json) || status=$?
  rm -rf -- "${config}"
  ((status == 0)) || fail "the shell of .envrc failed to load (exit ${status}); see the log above"
  [[ ${env} != *'"NIX_DIRENV_DID_FALLBACK"'* ]] || fail "the shell failed, and nix-direnv fell back to a previous one"
}

# check_hooks: the pre-commit hook and the store paths that it and the
# configuration of pre-commit name exist; prints what it checked.
check_hooks() {
  local top hooks hook config hooks_path paths path missing=()
  if ! top=$(git rev-parse --show-toplevel 2>/dev/null); then
    checked="not a git repository, no hooks"
    notice "not a git repository: skipping the git hooks"
    return 0
  fi
  hooks=$(git rev-parse --path-format=absolute --git-path hooks)
  hook=${hooks}/pre-commit
  config=${top}/.pre-commit-config.yaml
  hooks_path=$(git config --get core.hooksPath) || true
  if [[ -z ${hooks_path} && ! -e ${config} && ! -L ${config} && ! -e ${hook} ]]; then
    checked="no git hooks configured"
    notice "no core.hooksPath, .pre-commit-config.yaml or pre-commit hook: skipping the git hooks"
    return 0
  fi
  [[ -f ${hook} && -x ${hook} ]] || fail "no executable pre-commit hook in ${hooks}"
  # A dangling link to the configuration names its missing store path.
  paths=$(
    {
      grep -ohE "${store_path}" -- "${hook}" || true
      if [[ -L ${config} ]]; then readlink -- "${config}"; fi
      if [[ -f ${config} ]]; then grep -ohE "${store_path}" -- "${config}" || true; fi
    } | grep -oE "${store_path}" | sort -u
  ) || true
  while IFS= read -r path; do
    [[ -z ${path} || -e ${path} ]] || missing+=("${path}")
  done <<<"${paths}"
  ((${#missing[@]} == 0)) || fail "the git hooks name store paths this store does not have: ${missing[*]}"
  local count=0
  [[ -z ${paths} ]] || count=$(wc -l <<<"${paths}")
  checked="pre-commit hook checked with ${count} store paths"
}

if (($#)); then
  printf 'usage: %s\nSets up the workspace in the working directory (ADR-0002).\n' "${name}" >&2
  exit 2
fi

workspace=$(pwd -P)
check_worktree "${workspace}"
relative_worktrees
direnv allow . || fail "direnv allow failed"
load_shell
checked=""
check_hooks
printf '%s: %s: shell loaded, %s\n' "${name}" "${workspace}" "${checked}"
