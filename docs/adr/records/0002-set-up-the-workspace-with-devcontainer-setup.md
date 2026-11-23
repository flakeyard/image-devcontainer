---
id: ADR-0002
title: Set up the workspace with devcontainer-setup
status: accepted
date: 2026-11-23
supersedes: []
superseded_by: []
related: [ADR-0001]
affects:
  [
    "setup/**",
    "nix/image/parts/devcontainer-setup.nix",
    "nix/image/parts/tools.nix",
    "scripts/smoke.sh",
    "tests/smoke/setup.sh",
    "tests/smoke/probes/setup-*.sh",
    "tests/fixture/**",
  ]
review_by:
---

## Context

Projects run `direnv allow && direnv exec . true` as the `postCreateCommand` of
their `devcontainer.json`, so that the development shell is built and its
shellHook installs the git hooks when the container is created
([FY-0012][fy-0012]). [FY-0042][fy-0042] makes that command exactly
`devcontainer-setup`, a command of the image, and supports worktrees only inside
the workspace. This record is the contract of that command.

Probes with direnv 2.37 and nix-direnv in the image established:

- direnv ignores the exit status of `.envrc`: `direnv exec . true` and
  `direnv export json` exit 0 when a command of `.envrc` fails.
- When the flake of `use flake` fails to evaluate or build, nix-direnv warns
  "Falling back to previous environment!", sets `NIX_DIRENV_DID_FALLBACK` and
  succeeds, also when there is no previous environment.
- With `strict_env = true` in `direnv.toml`, direnv runs `.envrc` with
  `set -euo pipefail`, and with `nix_direnv_disallow_fallback` in `direnvrc`,
  `use flake` fails instead of falling back. `direnv export json` then exits 1
  on a failing command, an unset variable and a failed evaluation or build.
- `direnv export` evaluates nothing when the variables of a loaded environment
  (`DIRENV_DIR`, `DIRENV_FILE`, `DIRENV_DIFF`, `DIRENV_WATCHES`) say that it is
  current.
- A worktree opened as the workspace has a `.git` file whose `gitdir` is a path
  of the host, outside the mount, which the container does not have. git fails
  in it, and the development shell installs no hooks.
- The git hooks name tools by `/nix/store` paths of the store they were
  installed from. A hook installed in another container, or on the host, names
  paths this store may not have.
- `git rev-parse --git-path hooks` is `core.hooksPath` when it is set, and
  `.git/hooks` of the common directory otherwise.

A failing `postCreateCommand` is the only sign of a broken setup that Dev
Containers tools show; a command that succeeds on a broken shell hides it until
the first commit.

## Decision

The image has the command `devcontainer-setup` in `/bin`, built with Nix like
the entrypoint, from `setup/devcontainer-setup.sh`. It amends
[ADR-0001](0001-dev-container-image.md): the command is one of the tools of the
image and part of its public API.

### Contract

`devcontainer-setup` takes no arguments; with any, it prints its usage and
exits 2. It runs in the workspace folder, as Dev Containers tools run
`postCreateCommand`, and may run again by hand. It does, in order, and stops at
the first failure with exit status 1 and a message on stderr that says what
failed:

1. **Worktree.** When `.git` is a file, its `gitdir` must exist and lie inside
   the mount that holds the workspace. Otherwise it refuses with
   `create worktrees inside the workspace, e.g. git worktree add .worktrees/<name>`.
   Worktrees inside the workspace share its mount and pass.
2. **Trust.** `direnv allow`.
3. **Shell.** It loads the shell strictly: `direnv export json` without the
   variables of a loaded environment, with a configuration directory of its own
   (`DIRENV_CONFIG`) whose `direnv.toml` sets `strict_env = true` and whose
   `direnvrc` sources the `direnvrc` of the user and calls
   `nix_direnv_disallow_fallback`. A non-zero exit status, and a loaded
   environment with `NIX_DIRENV_DID_FALLBACK`, fail. The log of direnv and Nix
   goes to stderr. This load runs the shellHook, which installs the hooks.
4. **Hooks.** Outside a git repository, or when it has no `core.hooksPath`, no
   `.pre-commit-config.yaml` in the top of the checkout and no pre-commit hook,
   it says that it skips the hooks. Otherwise the executable `pre-commit` hook
   must exist in `git rev-parse --git-path hooks`, and every `/nix/store` path
   that it or `.pre-commit-config.yaml` names must exist.
5. **Summary.** One line on stdout that names the workspace and what was
   checked, then exit 0.

The settings of step 3 apply only to this load: the user's direnv loads the
shell as before, from the cache the strict load built.

### Tests

The smoke tests of the image ([ADR-0001](0001-dev-container-image.md)) run the
command in the container: a working project passes, also in a worktree inside
the workspace; a broken shell fails; a worktree whose `gitdir` is outside the
mount fails with the message; a hook whose tool is missing from the store fails;
a project without hooks passes with the notice.

## Constraints

- `devcontainer-setup` MUST be on the `PATH` of `dev`, built with Nix from the
  `flake.lock` of this repository, and MUST pass shellcheck.
- It MUST take no arguments and MUST exit 2 when given any.
- It MUST run in the workspace folder, its working directory.
- It MUST run the steps above in their order and MUST exit 1 at the first one
  that fails, with a message on stderr.
- It MUST refuse a `.git` file whose `gitdir` does not exist or is outside the
  mount that holds the workspace, with a message that says to create worktrees
  inside the workspace and shows `git worktree add .worktrees/<name>`.
- It MUST load the shell so that a failing command of `.envrc` and a failed
  evaluation or build of the shell fail, and MUST NOT accept a fallback to a
  previous environment. `direnv exec . true` MUST NOT be the check.
- It MUST check the `pre-commit` hook at `git rev-parse --git-path hooks` and
  every store path that the hook and `.pre-commit-config.yaml` name, unless the
  checkout has no hooks configuration, which it MUST then say.
- It MUST end with one summary line on stdout when it succeeds.
- Its name, its arguments, its exit statuses and the conditions under which it
  fails are public API; the texts of its messages, apart from the worktree
  message above, are not.
- The smoke tests MUST cover a working project, a broken shell and a worktree
  outside the mount.

## Consequences

- (+) A broken shell, a missing hook or an outside worktree fails the creation
  of the container where Dev Containers tools show it, not at the first commit.
- (+) The setup is one command in every `devcontainer.json`, maintained and
  tested once, here.
- (−) The strict load runs `.envrc` with `set -euo pipefail`: an `.envrc` that
  uses an unset variable or a failing command loads for direnv but fails here.
- (−) The strict load reads only the `direnvrc` of the user, not the files of
  `lib/` in its configuration directory or the settings of its `direnv.toml`.
- (±) A change of the contract is a release of the image, and projects get it
  with the digest.

## Alternatives considered

- **`direnv allow && direnv exec . true`.** Succeeds on a broken shell, as the
  probes showed.
- **`direnv export json` with the configuration of the user.** Succeeds on a
  failing `.envrc` and on a fallback of nix-direnv.
- **Checking a variable of the shell.** Works only for shells that set a known
  variable; the image is generic.
- **The setup as a shell line in every `devcontainer.json`.** Copies the logic
  into every repository ([FY-0035][fy-0035]), and no tests run it.
- **A Dev Containers feature.** [ADR-0001](0001-dev-container-image.md) excludes
  their support.

[fy-0012]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0012-develop-in-container.md
[fy-0035]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0035-extract-logic-that-has-two-users.md
[fy-0042]: https://github.com/flakeyard/decisions/tree/main/docs/adr/records
