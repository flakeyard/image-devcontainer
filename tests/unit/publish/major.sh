# shellcheck shell=bash
# Tests of scripts/publish/major.sh, with a stub of crane and a registry in a
# directory.
# shellcheck disable=SC2154 # work and registry come from setup

repo=ghcr.io/flakeyard/image-devcontainer

stubbed_setup
for version in 1.2.3 1.10.0 1.9.9 2.0.0; do
  echo "sha256:$(printf '%s' "$version" | sha256sum | cut -d' ' -f1)" >"$registry/tags/v$version"
done
newest=$(cat "$registry/tags/v1.10.0")
run "publish-major: points vX at the newest release of the major" ok scripts/publish/major.sh -- "$repo" 1
expect_tag v1 "$newest"
expect message "v1 now points at v1.10.0"
: >"$work/calls"
run "publish-major: a rerun changes nothing" ok scripts/publish/major.sh -- "$repo" 1
expect no-calls
finish

stubbed_setup
run "publish-major: fails without a release of the major" fail scripts/publish/major.sh -- "$repo" 3
expect message "no release of major version 3"
finish
