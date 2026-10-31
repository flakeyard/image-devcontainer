# Changelog

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
