#!/usr/bin/env bash
# Unit tests of scripts/publish/verify.sh, with stubs of crane, regctl, docker
# and gh and a registry in a directory. The release is published with
# scripts/publish/index.sh. Inputs (environment): SCRIPTS, the scripts
# directory; STUBS, the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

repo=ghcr.io/flakeyard/image-devcontainer
amd64=sha256:$(printf 'a%.0s' {1..64})
arm64=sha256:$(printf 'b%.0s' {1..64})

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls REGISTRY=$work/registry
  export PATH=$STUBS:$PATH
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags"
  : >"$CALLS"
  unset ATTESTED
  # The platform manifests of a release, pushed by digest.
  for digest in "$amd64" "$arm64"; do
    printf '%s' '{"mediaType":"application/vnd.docker.distribution.manifest.v2+json"}' >"$REGISTRY/manifests/$digest"
  done
}

# published: a release 1.2.3 as publish-index leaves it; prints its digest.
published() {
  "$SCRIPTS/publish/index.sh" "$repo" 1.2.3 abc123 "$amd64" "$arm64" 2>/dev/null
}
verify() {
  "$SCRIPTS/publish/verify.sh" flakeyard/image-devcontainer "$repo" "$index" 1.2.3 abc123 amd64 "$1"
}

setup
index=$(published)
export ATTESTED=1
run "publish-verify: a complete release" ok verify "$amd64"
expect message "Verified $repo:v1.2.3@$index on amd64"
expect called "--signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml"
finish

setup
index=$(published)
export ATTESTED=1
run "publish-verify: another tested digest" fail verify "$arm64"
expect message "was tested"
finish

setup
index=$(published)
echo "sha256:$(printf 'd%.0s' {1..64})" >"$REGISTRY/tags/v1.2.3"
export ATTESTED=1
run "publish-verify: the release tag points elsewhere" fail verify "$amd64"
expect message "not at $index"
finish

setup
index=$(published)
run "publish-verify: missing attestations" fail verify "$amd64"
finish

summary
