# Changelog

## [0.1.5](https://github.com/flakeyard/image-devcontainer/compare/v0.1.4...v0.1.5) (2026-11-11)


### Bug Fixes

* **deps:** update flakeyard/action-shell-lib action to v0.1.3 ([#83](https://github.com/flakeyard/image-devcontainer/issues/83)) ([9ae8c0f](https://github.com/flakeyard/image-devcontainer/commit/9ae8c0f92918b33d51c4c397cbfc17229552f3c0))

## [0.1.4](https://github.com/flakeyard/image-devcontainer/compare/v0.1.3...v0.1.4) (2026-11-10)


### Bug Fixes

* list attestations and read the git tag through the shell library ([#81](https://github.com/flakeyard/image-devcontainer/issues/81)) ([2cf75de](https://github.com/flakeyard/image-devcontainer/commit/2cf75deea88bb050a1bd8a67a503918cb6cede0c))

## [0.1.3](https://github.com/flakeyard/image-devcontainer/compare/v0.1.2...v0.1.3) (2026-11-10)


### Bug Fixes

* **deps:** update flake input nixpkgs to c56a87d ([#66](https://github.com/flakeyard/image-devcontainer/issues/66)) ([21d1de1](https://github.com/flakeyard/image-devcontainer/commit/21d1de1cd34b691e1bf19ac9cd9f22fa9026ac46))

## [0.1.2](https://github.com/flakeyard/image-devcontainer/compare/v0.1.1...v0.1.2) (2026-11-10)


### Bug Fixes

* **deps:** update flake input flake-parts to ea2630b ([#65](https://github.com/flakeyard/image-devcontainer/issues/65)) ([f40a162](https://github.com/flakeyard/image-devcontainer/commit/f40a1621bd19109da5b3851c783c1bd231f7d389))

## [0.1.1](https://github.com/flakeyard/image-devcontainer/compare/v0.1.0...v0.1.1) (2026-11-05)


### Bug Fixes

* entrypoint mount detection and a bounded daemon log ([#44](https://github.com/flakeyard/image-devcontainer/issues/44)) ([81fa352](https://github.com/flakeyard/image-devcontainer/commit/81fa352d614a5e95ecffb5acf0d095e45372cd29))
* idempotent release notes and a clean rebuild check ([#43](https://github.com/flakeyard/image-devcontainer/issues/43)) ([8d7f0fe](https://github.com/flakeyard/image-devcontainer/commit/8d7f0fe4e1e60168742e6b8f6e751576195a376b))
* tag the manifest list only after its attestation ([#41](https://github.com/flakeyard/image-devcontainer/issues/41)) ([2a31537](https://github.com/flakeyard/image-devcontainer/commit/2a315374654554dddb9c4bc89b96c99f1924452b))
* the image root and the OpenSSH client without stray entries ([#42](https://github.com/flakeyard/image-devcontainer/issues/42)) ([473fd89](https://github.com/flakeyard/image-devcontainer/commit/473fd89b4529ee93831dacd5d932e4872fc1bfa0))
* verify the manifest list against the commit of its git tag ([#47](https://github.com/flakeyard/image-devcontainer/issues/47)) ([33eed76](https://github.com/flakeyard/image-devcontainer/commit/33eed764e95df3bfdf3ba694011497fb3a295fa1))

## 0.1.0 (2026-10-31)


### Features

* assemble the image with nix-ld, GC roots and labels ([#4](https://github.com/flakeyard/image-devcontainer/issues/4)) ([16f74f3](https://github.com/flakeyard/image-devcontainer/commit/16f74f35aaf6e8d5e1fc49694c53da59accc1a8b))
* check reproducibility and size of the image ([#5](https://github.com/flakeyard/image-devcontainer/issues/5)) ([2d36dc2](https://github.com/flakeyard/image-devcontainer/commit/2d36dc2c2d22b0cc457db92ec9de3893857d10ab))
* entrypoint that adapts dev, runs the Nix daemon and drops to dev ([#2](https://github.com/flakeyard/image-devcontainer/issues/2)) ([119291a](https://github.com/flakeyard/image-devcontainer/commit/119291ae475a59688904b3913468b59c6e0b4e7d))
* flake with the tools, users and Nix settings of the image ([#1](https://github.com/flakeyard/image-devcontainer/issues/1)) ([71c9580](https://github.com/flakeyard/image-devcontainer/commit/71c958060cb4f35ab487592709b92ab6b1f9087d))
* publication scripts with registry stubs ([#10](https://github.com/flakeyard/image-devcontainer/issues/10)) ([4f3f16a](https://github.com/flakeyard/image-devcontainer/commit/4f3f16a1a4be06c1c637d67138f1634a7c76da59))
* release and publish the image ([#11](https://github.com/flakeyard/image-devcontainer/issues/11)) ([d63742b](https://github.com/flakeyard/image-devcontainer/commit/d63742b6e6af139cc1348b31518a8197035d9f37))
* SBOM and license checks of the image ([#9](https://github.com/flakeyard/image-devcontainer/issues/9)) ([7a526e8](https://github.com/flakeyard/image-devcontainer/commit/7a526e85db247aa2d02f887c83c16ca12cb212c5))
* weekly checks of the nixpkgs end of life and of release rebuilds ([#12](https://github.com/flakeyard/image-devcontainer/issues/12)) ([be8b775](https://github.com/flakeyard/image-devcontainer/commit/be8b7753496bd2ac0fb64459dfbaf405b747e5a2))


### Bug Fixes

* a failing command fails its smoke test, not the whole suite ([#26](https://github.com/flakeyard/image-devcontainer/issues/26)) ([640d12e](https://github.com/flakeyard/image-devcontainer/commit/640d12ef48ca7332e67b2e3a2db9cf1ff3619137))
* attestations are not bound to the release commit ([#18](https://github.com/flakeyard/image-devcontainer/issues/18)) ([6e5f3b8](https://github.com/flakeyard/image-devcontainer/commit/6e5f3b8b5fd7bf096e6a71afefbd2975e29786ff))
* close the paths from dev to root found by the audit ([#14](https://github.com/flakeyard/image-devcontainer/issues/14)) ([9fa7296](https://github.com/flakeyard/image-devcontainer/commit/9fa7296ce6ec77168a5c701ac0c7cbafe55bf9f2))
* entrypoint leaves a mounted home alone and isolates root's Nix ([#20](https://github.com/flakeyard/image-devcontainer/issues/20)) ([73a4455](https://github.com/flakeyard/image-devcontainer/commit/73a4455ced9bd1fc7cdffa1ccfd2a0e400df20bc))
* gates fail closed ([#22](https://github.com/flakeyard/image-devcontainer/issues/22)) ([e0dc9c5](https://github.com/flakeyard/image-devcontainer/commit/e0dc9c58a07737fa141fa6192ea5eec078f2dca0))
* stricter and idempotent publication ([#16](https://github.com/flakeyard/image-devcontainer/issues/16)) ([42f4a66](https://github.com/flakeyard/image-devcontainer/commit/42f4a66cd5f108c0fc83737029428113e0cff332))
* the license check cannot be passed by an incomplete SBOM ([#15](https://github.com/flakeyard/image-devcontainer/issues/15)) ([645eaba](https://github.com/flakeyard/image-devcontainer/commit/645eaba5cd0621be6b4be30e6e465cbb6983f292))
