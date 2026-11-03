#!/usr/bin/env bash
# Unit tests of scripts/publish/verify.sh, with stubs of crane, regctl, docker
# and gh and a registry in a directory. The release is published with
# scripts/publish/index.sh and scripts/publish/tag.sh. Inputs (environment):
# SCRIPTS, the scripts directory; STUBS, the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

repo=ghcr.io/flakeyard/image-devcontainer
amd64=sha256:$(printf 'a%.0s' {1..64})
arm64=sha256:$(printf 'b%.0s' {1..64})
revision=abc123 other=def456

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls REGISTRY=$work/registry
  export PATH=$STUBS:$PATH
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags"
  : >"$CALLS"
  unset ATTESTED ATTESTED_COMMIT TAG_COMMIT
  # The platform manifests of a release, pushed by digest.
  for digest in "$amd64" "$arm64"; do
    printf '%s' '{"mediaType":"application/vnd.docker.distribution.manifest.v2+json"}' >"$REGISTRY/manifests/$digest"
  done
}

# published: a release 1.2.3 as publish-index and publish-tag leave it;
# prints its digest.
published() {
  local digest
  digest=$("$SCRIPTS/publish/index.sh" "$repo" 1.2.3 "$revision" "$amd64" "$arm64" 2>/dev/null)
  "$SCRIPTS/publish/tag.sh" "$repo" 1.2.3 "$digest" >/dev/null 2>&1
  echo "$digest"
}
verify() {
  "$SCRIPTS/publish/verify.sh" flakeyard/image-devcontainer "$repo" "$index" 1.2.3 "$revision" amd64 "$1"
}
# attested: the git tag and the attestations are of the release commit.
attested() { export ATTESTED=1 TAG_COMMIT=$revision ATTESTED_COMMIT=$revision; }

setup
index=$(published)
attested
run "publish-verify: a complete release" ok verify "$amd64"
expect message "Verified $repo:v1.2.3@$index on amd64"
expect called "--signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml"
expect called "verify oci://$repo@$index --repo flakeyard/image-devcontainer --signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml --deny-self-hosted-runners --source-digest $revision"
expect not_called "verify oci://$repo@$amd64 --repo flakeyard/image-devcontainer --signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml --deny-self-hosted-runners --source-digest"
finish

setup
index=$(published)
attested
run "publish-verify: another tested digest" fail verify "$arm64"
expect message "was tested"
finish

setup
index=$(published)
echo "sha256:$(printf 'd%.0s' {1..64})" >"$REGISTRY/tags/v1.2.3"
attested
run "publish-verify: the release tag points elsewhere" fail verify "$amd64"
expect message "not at $index"
finish

setup
index=$(published)
run "publish-verify: missing attestations" fail verify "$amd64"
finish

setup
index=$(published)
attested
export ATTESTED_COMMIT=$other
run "publish-verify: the list is attested for another commit" fail verify "$amd64"
expect message "another commit"
finish

setup
index=$(published)
attested
export TAG_COMMIT=$other
run "publish-verify: the git tag is at another commit" fail verify "$amd64"
expect message "the git tag v1.2.3 is at $other, not at $revision"
finish

setup
index=$(published)
attested
unset TAG_COMMIT
run "publish-verify: no git tag" fail verify "$amd64"
expect message "cannot read the git tag v1.2.3"
finish

summary
