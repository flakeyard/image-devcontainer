# image-devcontainer

A dev container image built with Nix: multi-user Nix, direnv and nix-direnv, and
the minimum a shell needs before a project shell exists. Projects get their
tools from their own `flake.lock` through `use flake`; the image contains no
toolchain, editor or language server. It works with any editor that supports the
Dev Containers specification, and with Docker and rootless Podman directly.

## Usage

Pin the image by the digest that the [release notes][releases] name:

```jsonc
// .devcontainer/devcontainer.json
{
  "image": "ghcr.io/flakeyard/image-devcontainer:v0@sha256:<digest>",
}
```

The image carries what Dev Containers tools need in its `devcontainer.metadata`
label: `remoteUser: dev`, `overrideCommand: false`, `init: true` and
`updateRemoteUserUID: true`. A project may add
`"postCreateCommand": "direnv allow"` and named volumes for state under
`/home/dev` that should survive recreating the container. The supported targets
are `/home/dev/.cache`, `/home/dev/.local/share` and `/home/dev/.vscode-server`:
the image has these directories, owned by `dev`, and Docker and Podman give a
new volume the owner of the directory it is mounted at. A new volume anywhere
else belongs to root, and `dev` cannot write to it.

A volume keeps the uid it was created with. The entrypoint never changes the
owner of a mount point, so when `dev` gets another uid than 1000, from `DEV_UID`
or the owner of the project, it cannot write to a new volume, which belongs to
uid 1000. Give the volume to that uid once, as root, with a file in it: Docker
fills an empty volume from the image again at every start.

```sh
docker run --rm --entrypoint sh -v cache:/home/dev/.cache \
  ghcr.io/flakeyard/image-devcontainer:v0@sha256:<digest> \
  -c 'touch /home/dev/.cache/.keep && chown -R 1001:1001 /home/dev/.cache'
```

Mount the project under `/home/dev` rather than at the default
`/workspaces/<name>` of Dev Containers tools:

```jsonc
{
  "workspaceMount": "source=${localWorkspaceFolder},target=/home/dev/${localWorkspaceFolderBasename},type=bind",
  "workspaceFolder": "/home/dev/${localWorkspaceFolderBasename}",
}
```

Builds run without a sandbox (see [Nix](#behaviour)), so any derivation of any
flake input of the project can read every file that its build user may read.
Only `dev` may enter `/home/dev`; a checkout at `/workspaces/<name>` usually is
readable by everyone, untracked files such as `.env` included. The label cannot
carry these settings, so every project sets them itself.

Without Dev Containers tools:

```sh
docker run --rm -it -v "$PWD:/home/dev/project" -w /home/dev/project \
  ghcr.io/flakeyard/image-devcontainer:v0@sha256:<digest> bash
```

With rootless Podman 4.3 or later, set in
`~/.config/containers/containers.conf`:

```toml
[containers]
userns = "keep-id:uid=1000,gid=1000"
```

A shared `devcontainer.json` cannot carry this setting, because Docker rejects
it.

## Behaviour

- **User.** Commands run as `dev`, with the home `/home/dev`. The container
  starts as root, and the image starts `tini` first, which handles signals from
  the start, forwards them to the process group of its child and reaps orphaned
  processes, also under the init process of the engine (`init: true`). It runs
  the entrypoint, which:
  1. gives `dev` the uid and gid of `DEV_UID` and `DEV_GID` when they are set,
     otherwise of the owner of the working directory when it is a mount point
     not owned by root, and the files of `dev` on the home directory's own file
     system with it; mounted files are left alone, and all of the home when it
     is a mount point itself;
  2. starts the Nix daemon, restarts it when it exits, and waits until it
     answers; with a read-only `/nix`, it says so and runs the command without
     the daemon. The daemon logs to `/var/log/nix-daemon.log`, which moves to
     `/var/log/nix-daemon.log.old` past 10 MiB. It runs in a process group of
     its own, without the terminal as its input, so that the signals of the
     command and of its terminal do not reach it. It gets no `SIGTERM` on
     `docker stop`: the kernel kills it with the container, which its SQLite
     database in WAL mode survives;
  3. runs the command as `dev` in its own place, so that the command gets the
     signals that `tini` forwards.

  `DEV_UID` sets the uid of `dev` and, unless `DEV_GID` is also set, its gid;
  `DEV_GID` alone is ignored. Without `DEV_UID`, the owner of a mounted working
  directory sets both. Both must be decimal numbers from 1 to 4294967294, and
  the uid must not belong to another user; a gid of another group keeps the
  current gid. The command never runs as root, whatever these variables say.
  Started without root, the entrypoint warns that the Nix daemon is not running
  and runs the command.

  The pipes, sockets and terminal (`docker run -t`) that the container engine
  makes the standard input, output and error belong to `dev`, so that it can
  reopen them as `/dev/stdin`, `/dev/stdout` and `/dev/stderr`; the terminal
  keeps its group. Files and named pipes keep their owner.

- **Environment.** Root's `PATH` is `/bin:/usr/bin`; `dev` gets
  `~/.nix-profile/bin` in front of it, from the entrypoint and from
  `/etc/bashrc`, because root must never run programs `dev` controls. The Nix
  processes of root, the daemon and the entrypoint's check that it answers, run
  with a fixed environment and `PATH`, so variables such as `NIX_CONFIG` or
  `XDG_CONFIG_HOME` set for the container reach only the commands, never root.
  Only the proxy variables `http_proxy`, `https_proxy`, `all_proxy` and
  `no_proxy`, in lower and upper case, pass to the daemon when set, because it
  downloads from the binary cache.

  The dynamic loader of glibc reads `LD_PRELOAD`, `LD_LIBRARY_PATH`, `LD_AUDIT`,
  `GCONV_PATH` and the like in every program before its first line, so no
  program of root starts with the variables of the container. `tini` is linked
  statically, and starts the entrypoint through `environ`, a small static
  program of this repository, which passes the variables to the entrypoint
  through a file descriptor and leaves it an empty environment. Of them, the
  entrypoint reads only `DEV_UID`, `DEV_GID` and the proxy variables; the
  command of `dev` gets them all, with `HOME`, `USER`, `LOGNAME` and `PATH` of
  its own, from `environ` again once root is dropped. The variables are never in
  the arguments of a process, which every process of the container can read in
  `/proc`. A command that is an executable file without `#!` runs with
  `/bin/sh`. The entrypoint runs in the privileged mode of bash, which ignores
  `BASH_ENV`, functions exported in the environment, `SHELLOPTS`, `BASHOPTS`,
  `CDPATH` and `GLOBIGNORE`. Dev Containers tools start the image through a
  `/bin/sh` of root of their own, which reads the variables of `containerEnv`
  before `tini` starts.

- **Capabilities.** The entrypoint and the Nix daemon need `CHOWN`,
  `DAC_OVERRIDE`, `FOWNER`, `SETUID` and `SETGID`, which Docker and Podman grant
  by default; without `FOWNER`, builds fail to set the permissions of their
  outputs.
- **Nix.** Nix 2.35 in multi-user mode: the store belongs to root and is written
  only by the daemon; builds run as build users. Only root is a trusted user, so
  `dev` cannot add substituters, and `accept-flake-config` is off. The only
  substituter is `cache.nixos.org`; other caches and keys go to
  `/etc/nix/local.conf`, which `/etc/nix/nix.conf` includes. The sandbox is off:
  it needs privileges a dev container does not have and would fall back
  silently; builds that must be isolated run in CI. Without it, a build runs as
  a build user with network access and reads every file in the container that is
  readable by everyone; `/home/dev` is not. Nix collects garbage when free disk
  space runs low.
- **Tools.** `nix`, `direnv`, `nix-direnv`, `bash`, coreutils, findutils,
  diffutils, `grep`, `sed`, `awk`, `tar`, `gzip`, `xz`, `bzip2`, `zstd`, `less`,
  procps, `which`, util-linux, `getent`, `curl`, `git`, the OpenSSH client
  without its server, CA certificates, time zones and service names. Interactive
  and login shells load the direnv hook.
- **Foreign binaries.** Editor servers built for other distributions run through
  nix-ld at the standard loader path, with `libstdc++` and `libgcc_s` besides
  glibc, as VS Code Server needs.

## Public API

An incompatible change of any of these is a major release
([ADR-0001](docs/adr/records/0001-dev-container-image.md)):

- the user `dev`, its home `/home/dev`, and the meaning of `DEV_UID` and
  `DEV_GID`;
- the behaviour of the entrypoint and the environment variables of the image;
- the settings of `/etc/nix/nix.conf` and `/etc/nix/local.conf`;
- the defaults in the `devcontainer.metadata` label;
- the tools above, by name;
- the Nix implementation and its minor version;
- the platforms `linux/amd64` and `linux/arm64`, the engines Docker, Dev
  Containers tools and rootless Podman, and the capabilities above.

Versions of the other tools are not part of the API.

## Verification

Every release is built by the release workflow of this repository from the
tagged commit. Verify the digest from the release notes of `vX.Y.Z` against the
commit of the git tag `vX.Y.Z` before you trust it:

```sh
repo=flakeyard/image-devcontainer
commit=$(gh api "repos/$repo/commits/tags/vX.Y.Z" --jq .sha)
gh attestation verify "oci://ghcr.io/$repo@sha256:<digest>" --repo "$repo" \
  --signer-workflow "$repo/.github/workflows/release.yaml" \
  --source-digest "$commit"
```

Only an approved release creates the git tag, and the check binds the digest to
it. The tags of the registry are a convenience: anyone who can write to the
package can move them, so the digest in the release notes and this check are
what to trust.

The digest in the release notes is that of the manifest list for both platforms.
Each platform manifest has a provenance attestation and a CycloneDX SBOM that
lists the license of every package (predicate type `https://cyclonedx.org/bom`).

## Registry

- `vX.Y.Z` is set once and never moved; `vX` points at the newest published
  `vX.Y.Z`; there is no `latest`. Both are set only after the manifest list has
  its provenance attestation.
- Platform manifests are pushed by digest without tags. The tags `sha256-*` hold
  the attestations. Neither is ever deleted, and nothing cleans up the package.
- The same commit yields the same digests. An update of `flake.lock` can change
  the digests even when the contents stay the same.
- A release that does not change the image has the platform digests of the
  previous one, and with them its platform attestations, which name the commit
  of the earlier release. The manifest list and its attestation are new; the
  list names the version and the commit of the release in its annotations.
- A failed publication is completed by re-running all jobs of the release
  workflow run; re-running only the failed jobs may lose the tested digests.

## Versioning

Releases follow [semantic versioning][versioning]; `0.y.z` releases are
pre-releases. A new patch or minor version of Nix is a release of the same
level, unless the release notes of Nix list incompatible changes. The image
follows the stable nixpkgs branch that `flake.lock` pins and moves to the next
one before its end of life ([FY-0036][fy-0036]); a new Nix minor version comes
to the image after `action-setup-nix` has released it.

## Development

- `nix flake check` checks the tools, the users and Nix settings, the entrypoint
  and the scripts with their unit tests (`tests/unit/`), that the image builds,
  and formatting (`nix fmt`).
- `nix run .#check-reproducible` rebuilds the derivations of the image that
  `cache.nixos.org` does not have with `--rebuild`, whatever the local store has
  built, and compares two streams of the image;
  `nix run .#check-size -- size-budget` compares its size with the budget.
- `nix run .#smoke -- tests/smoke` loads the image into Docker and runs the
  smoke tests, including VS Code Server and the Dev Containers tools with Docker
  and rootless Podman. They need Docker, Podman and passwordless sudo, as on
  GitHub-hosted runners.
- `nix run .#check-licenses -- sbom.cdx.json` generates the SBOM and checks the
  licenses.

CI runs all of them on both architectures, after
[action-flake-lock][action-flake-lock] has checked `flake.lock` before any
evaluation of the flake ([FY-0017][fy-0017]), and ends with
[workflow-check][workflow-check], which checks the pull request title,
`renovate.json` and the release behind its preset tag and reports the only
required check, `check / required` ([FY-0034][fy-0034]). The release workflow
publishes the image ([FY-0032][fy-0032]); its jobs that push to the package or
attest run in the environment `publish` and wait until the owner approves them.
`scorecard.yaml` runs OpenSSF Scorecard on `main`. The weekly run of `test.yaml`
also rebuilds the newest release on both architectures to compare its digests
with the registry, in the job `rebuild`, which other events skip. To rebuild on
demand, use Re-run all jobs on the newest scheduled run of `test.yaml`.
`action-flake-lock` warns from 30 days before the nixpkgs branch of `flake.lock`
reaches its end of life and fails the weekly run after it.

Every app has a file under `nix/apps/` with its description and tools, and a
script at the same path under `scripts/`; it is named after the path, so
`nix/apps/check/size.nix` and `scripts/check/size.sh` are the app `check-size`.
The apps that build the image do it through `scripts/lib/image.sh`. The apps
`publish-*` publish the image and share the checks in `scripts/publish/lib.sh`,
which the action `attest-once` sources as well. The unit tests of a script are
at its path under `tests/unit/`; those of the release workflow and its scripts
are in `tests/unit/release/`, and the static tests of `test.yaml` in
`tests/unit/workflows/`. [`tests/run.sh`](tests/run.sh) runs them, and
`tests/unit/entrypoint.sh` and `tests/unit/environ.sh` those of the entrypoint
and `environ`, with the harness and the stubs of `gh`, `date` and `sleep` of
[action-shell-lib][action-shell-lib] and the other stubs in `tests/bin/`. The
action `attest-once` and the app `publish-verify` call the GitHub API through
`github/api.sh` of the library. The jobs of `release.yaml` that attest pin the
library for the action; the job `image` of `test.yaml` pins the same commit, at
which `nix flake check` and the app fetch it. Alone, `tests/run.sh` needs
`SHELL_LIB` set to a checkout of the library and mikefarah `yq`.

## Bootstrap

This repository is bootstrapped under [FY-0022][fy-0022]. Until their providers
are released:

- actionlint, zizmor, shellcheck, shfmt, statix, deadnix, Prettier,
  markdownlint, typos and `reuse lint` run locally before every pull request
  (provider: `workflow-check` and the atoms).

## License

[MIT](LICENSE).

[releases]: https://github.com/flakeyard/image-devcontainer/releases
[versioning]: https://github.com/flakeyard/.github/blob/main/VERSIONING.md
[fy-0036]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0036-check-the-end-of-life-of-nixpkgs-in-flake-lock.md
[fy-0032]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0032-publish-images-behind-an-approval.md
[fy-0017]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0017-atom-contract.md
[fy-0022]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0022-bootstrap.md
[fy-0034]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0034-check-every-repository-with-workflow-check.md
[workflow-check]: https://github.com/flakeyard/workflow-check
[action-flake-lock]: https://github.com/flakeyard/action-flake-lock
[action-shell-lib]: https://github.com/flakeyard/action-shell-lib
