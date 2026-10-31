#!/usr/bin/env bash
# Unit tests of scripts/publish/major.sh, with a stub of crane and a registry
# in a directory. Inputs (environment): SCRIPTS, the scripts directory; STUBS,
# the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

repo=ghcr.io/flakeyard/image-devcontainer

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls REGISTRY=$work/registry
  export PATH=$STUBS:$PATH
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags"
  : >"$CALLS"
}

setup
for version in 1.2.3 1.10.0 1.9.9 2.0.0; do
  echo "sha256:$(printf '%s' "$version" | sha256sum | cut -d' ' -f1)" >"$REGISTRY/tags/v$version"
done
newest=$(cat "$REGISTRY/tags/v1.10.0")
run "publish-major: points vX at the newest release of the major" ok "$SCRIPTS/publish/major.sh" "$repo" 1
expect tag v1 "$newest"
expect message "v1 now points at v1.10.0"
: >"$CALLS"
run "publish-major: a rerun changes nothing" ok "$SCRIPTS/publish/major.sh" "$repo" 1
expect calls ""
finish

setup
run "publish-major: fails without a release of the major" fail "$SCRIPTS/publish/major.sh" "$repo" 3
expect message "no release of major version 3"
finish

summary
