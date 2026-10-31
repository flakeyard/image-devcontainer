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
`"postCreateCommand": "direnv allow"` and named volumes for caches under
`/home/dev` that should survive recreating the container.

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
  starts as root; the entrypoint then:
  1. gives `dev` the uid and gid of `DEV_UID` and `DEV_GID` when they are set,
     otherwise of the owner of the working directory when it is a mount point
     not owned by root, and the files of `dev` on the home directory's own file
     system with it; mounted files are left alone;
  2. starts the Nix daemon, restarts it when it exits, and waits until it
     answers;
  3. runs the command as `dev` under `tini`, which reaps orphaned processes and
     forwards signals.

  `DEV_UID` sets the uid of `dev` and, unless `DEV_GID` is also set, its gid;
  `DEV_GID` alone is ignored. Without `DEV_UID`, the owner of a mounted working
  directory sets both. Both must be decimal numbers from 1 to 4294967294, and
  the uid must not belong to another user; a gid of another group keeps the
  current gid. The command never runs as root, whatever these variables say.
  Started without root, the entrypoint warns that the Nix daemon is not running
  and runs the command.

- **Environment.** Root's `PATH` is `/bin:/usr/bin`; `dev` gets
  `~/.nix-profile/bin` in front of it, from the entrypoint and from
  `/etc/bashrc`, because root must never run programs `dev` controls. The Nix
  daemon runs with a fixed environment, so variables such as `NIX_CONFIG` set
  for the container reach only the commands, never the daemon.

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
  silently; builds that must be isolated run in CI. Nix collects garbage when
  free disk space runs low.
- **Tools.** `nix`, `direnv`, `nix-direnv`, `bash`, coreutils, findutils,
  diffutils, `grep`, `sed`, `awk`, `tar`, `gzip`, `xz`, `bzip2`, `zstd`, `less`,
  procps, `which`, util-linux, `getent`, `curl`, `git`, the OpenSSH client, CA
  certificates, time zones and service names. Interactive and login shells load
  the direnv hook.
- **Foreign binaries.** Editor servers built for other distributions run through
  nix-ld at the standard loader path, with `libstdc++` and `libgcc_s` besides
  glibc, as VS Code Server needs.

## Public API

An incompatible change of any of these is a major release ([FY-0005][fy-0005]):

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
tagged commit. Verify the image and its SBOM before you trust a digest:

```sh
ref=ghcr.io/flakeyard/image-devcontainer@sha256:<digest>
gh attestation verify "oci://$ref" --repo flakeyard/image-devcontainer \
  --signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml
```

The digest in the release notes is that of the manifest list for both platforms.
Each platform manifest has a provenance attestation and a CycloneDX SBOM that
lists the license of every package (predicate type `https://cyclonedx.org/bom`).

## Registry

- `vX.Y.Z` is set once and never moved; `vX` points at the newest published
  `vX.Y.Z`; there is no `latest`.
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
follows the stable nixpkgs branch in `nixpkgs-eol` and moves to the next one
before its end of life ([FY-0026][fy-0026]); a new Nix minor version comes to
the image after `action-setup-nix` has released it.

## Development

- `nix flake check` checks the tools, the users and Nix settings, the entrypoint
  and the scripts with their unit tests (`tests/unit/`), that the image builds,
  and formatting (`nix fmt`).
- `nix run .#check-reproducible` rebuilds the derivations of the image that are
  not in a binary cache with `--rebuild` and compares two streams of the image;
  `nix run .#check-size -- size-budget` compares its size with the budget.
- `nix run .#smoke -- tests/smoke` loads the image into Docker and runs the
  smoke tests, including VS Code Server and the Dev Containers tools with Docker
  and rootless Podman. They need Docker, Podman and passwordless sudo, as on
  GitHub-hosted runners.
- `nix run .#check-licenses -- sbom.cdx.json` generates the SBOM and checks the
  licenses.

CI runs all of them on both architectures; the release workflow publishes the
image ([FY-0027][fy-0027]). The weekly workflow `maintenance.yaml`, which is
not a required check, warns before the nixpkgs branch in `nixpkgs-eol` reaches
its end of life and rebuilds the newest release to compare its digests with
the registry.

## Bootstrap

This repository is bootstrapped under [FY-0022][fy-0022]. Until their providers
are released:

- actionlint, zizmor, shellcheck, shfmt, statix, deadnix, Prettier,
  markdownlint, typos and `reuse lint` run locally before every pull request
  (provider: `workflow-check` and the atoms);
- pull request titles are checked by the reviewer (provider: `workflow-check`);
- rulesets require no status checks (provider: `workflow-check`);
- the jobs `pending` and `required` of `.github/workflows/test.yaml` and
  `.github/scripts/commit-status.sh` and `required.sh` are a copy shared with
  the other bootstrapped repositories (provider: `workflow-check`);
- OpenSSF Scorecard is not run (provider: `workflow-check`).

## License

[MIT](LICENSE).

[releases]: https://github.com/flakeyard/image-devcontainer/releases
[versioning]: https://github.com/flakeyard/.github/blob/main/VERSIONING.md
[fy-0005]: https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0005-dev-container-image.md
[fy-0026]: https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0026-stable-nixpkgs.md
[fy-0027]: https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0027-publish-image.md
[fy-0022]: https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0022-bootstrap.md
