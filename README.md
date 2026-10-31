# image-devcontainer

A dev container image built with Nix: multi-user Nix, direnv and nix-direnv, and
the minimum a shell needs before a project shell exists.

The image is in development; it is not published yet.

## Development

`nix flake check` runs every check of the repository: the tools of the image
build and allow redistribution, the image uses one Nix version, users and Nix
settings are consistent, the entrypoint passes its unit tests
(`tests/unit/entrypoint.sh`), and Nix files are formatted (`nix fmt`).

## Bootstrap

This repository is bootstrapped under [FY-0022][fy-0022]. Until their providers
are released:

- actionlint, zizmor, shellcheck, shfmt, statix, deadnix, Prettier,
  markdownlint, typos and `reuse lint` run locally before every pull request
  (provider: `workflow-check` and the atoms);
- pull request titles are checked by the reviewer (provider: `workflow-check`);
- rulesets require no status checks (provider: `workflow-check`);
- the jobs `pending` and `required` of `.github/workflows/test.yaml` and
  `.github/scripts/` are a copy shared with the other bootstrapped repositories
  (provider: `workflow-check`);
- OpenSSF Scorecard is not run (provider: `workflow-check`).

[fy-0022]: https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0022-bootstrap.md
