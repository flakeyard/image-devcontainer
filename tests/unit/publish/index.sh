#!/usr/bin/env bash
# Unit tests of scripts/publish/index.sh, with stubs of crane and regctl and a
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
  export CALLS=$work/calls REGISTRY=$work/registry
  export PATH=$STUBS:$PATH
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags"
  : >"$CALLS"
  unset CRANE_DENIED
  # The platform manifests of a release, pushed by digest.
  for digest in "$amd64" "$arm64"; do
    printf '%s' '{"mediaType":"application/vnd.docker.distribution.manifest.v2+json"}' >"$REGISTRY/manifests/$digest"
  done
}

publish() { "$SCRIPTS/publish/index.sh" "$repo" 1.2.3 abc123 "$amd64" "$arm64"; }

setup
run "publish-index: pushes the list by digest, then tags it" ok publish
digest=$(printed)
expect calls "put $digest;tag v1.2.3 $digest"
expect tag v1.2.3 "$digest"
if still_passing; then
  jq -e '.manifests[0].platform.architecture == "amd64" and .manifests[1].platform.architecture == "arm64"
    and .annotations["org.opencontainers.image.version"] == "1.2.3"
    and .annotations["org.opencontainers.image.revision"] == "abc123"' \
    "$REGISTRY/manifests/$digest" >/dev/null || report "index: $(cat "$REGISTRY/manifests/$digest")"
fi
finish

# The digest of the canonical JSON of the list for the inputs of publish: a
# change of its bytes changes the digest consumers pin.
setup
run "publish-index: the exact bytes of the list" ok publish
pinned=sha256:2268211f761ccdcc84ce34b5d106de9887490dffe29561f97410bdb00fd75fbb
if still_passing && [[ $(printed) != "$pinned" ]]; then
  report "digest $(printed), not $pinned: $(cat "$REGISTRY/manifests/$(printed)")"
fi
finish

setup
run "publish-index: the same release gives the same digest" ok publish
first=$(printed)
: >"$CALLS"
run "publish-index: a rerun changes no tag" ok publish
expect output "$first"
expect calls "put $first"
finish

setup
echo "sha256:$(printf 'c%.0s' {1..64})" >"$REGISTRY/tags/v1.2.3"
run "publish-index: refuses to move a release tag" fail publish
expect message "release tags are immutable"
expect calls ""
finish

setup
export CRANE_DENIED=1
run "publish-index: fails when the tag cannot be read" fail publish
expect message "cannot read $repo:v1.2.3"
expect calls ""
finish

setup
rm "$REGISTRY/manifests/$arm64"
run "publish-index: needs both platform manifests in the registry" fail publish
expect calls ""
finish

setup
run "publish-index: descriptor sizes are the bytes of the manifests" ok publish
if still_passing; then
  size=$(wc -c <"$REGISTRY/manifests/$amd64")
  jq -e --argjson s "$size" '.manifests[0].size == $s' "$REGISTRY/manifests/$(printed)" >/dev/null ||
    report "size is not $size"
fi
finish

setup
printf '%s' '{"mediaType":"application/vnd.oci.image.index.v1+json"}' >"$REGISTRY/manifests/$arm64"
run "publish-index: a platform must be an image manifest" fail publish
expect message "is not an image manifest"
expect calls ""
finish

setup
run "publish-index: first run" ok publish
digest=$(printed)
rm "$REGISTRY/tags/v1.2.3" && echo "$digest" >"$REGISTRY/tags/v1.2.3"
: >"$CALLS"
run "publish-index: a tag already at the digest is left alone" ok publish
expect calls "put $digest"
finish

setup
run "publish-index: rejects a malformed version" fail \
  "$SCRIPTS/publish/index.sh" "$repo" 1.2 abc "$amd64" "$arm64"
expect calls ""
finish

summary
