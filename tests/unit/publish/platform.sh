#!/usr/bin/env bash
# Unit tests of scripts/publish/platform.sh, with stubs of nix and crane and a
# registry in a directory. Inputs (environment): SCRIPTS, the scripts
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
  export CALLS=$work/calls REGISTRY=$work/registry STREAM=$work/stream
  export PATH=$STUBS:$PATH TARBALL_DIGEST=$amd64 PUBLISH_DIGEST=$SCRIPTS/publish/digest.sh
  mkdir -p "$REGISTRY/manifests"
  : >"$CALLS"
  printf '#!%s\necho archive\n' "$(command -v bash)" >"$STREAM"
  chmod +x "$STREAM"
}

setup
run "publish-platform: pushes the tested digest" ok "$SCRIPTS/publish/platform.sh" "$repo" "$amd64"
expect calls "push $amd64"
expect output "$amd64"
finish

setup
run "publish-platform: refuses another digest" fail "$SCRIPTS/publish/platform.sh" "$repo" "$arm64"
expect message "but $arm64 was tested"
expect calls ""
finish

setup
# A publish-digest that records its flake.
cat >"$work/publish-digest" <<STUB
#!$(command -v bash)
echo "publish-digest \$2" >>"\$CALLS"
echo "\$TARBALL_DIGEST"
STUB
chmod +x "$work/publish-digest"
PUBLISH_DIGEST=$work/publish-digest run "publish-platform: computes the digest with publish-digest" ok \
  "$SCRIPTS/publish/platform.sh" "$repo" "$amd64" "$work/flake"
expect calls "publish-digest $work/flake;push $amd64"
finish

setup
run "publish-platform: rejects a malformed digest" fail "$SCRIPTS/publish/platform.sh" "$repo" latest
expect calls ""
finish

summary
