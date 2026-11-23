# shellcheck shell=bash
# Makes the working directory a git repository with a pre-commit hook whose
# interpreter is the bash of the image, or, with the argument "missing", a
# store path that does not exist; runs devcontainer-setup in it and in a
# worktree inside it, and prints their exit statuses. The script comes on
# stdin: the commands must not read it.
interpreter=$(readlink -f /bin/bash)
if [[ ${1:-} == missing ]]; then
  interpreter=/nix/store/00000000000000000000000000000000-missing/bin/bash
fi
{
  git init -q
  git add -A
  git -c user.name=smoke -c user.email=smoke@invalid -c commit.gpgsign=false commit -qm fixture
  printf '#!%s\nexit 0\n' "${interpreter}" >.git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  devcontainer-setup
  echo "workspace exit $?"
  git worktree add -q .worktrees/inner && cd .worktrees/inner && devcontainer-setup
  echo "inner exit $?"
} </dev/null
