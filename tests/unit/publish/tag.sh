#!/usr/bin/env bash
# Unit tests of scripts/publish/tag.sh, with stubs of crane and regctl and a
# registry in a directory. Inputs (environment): SCRIPTS, the scripts
# directory; STUBS, the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

repo=ghcr.io/flakeyard/image-devcontainer
amd64=$(digest_of a)
arm64=$(digest_of b)
list=$(digest_of d)
other=$(digest_of c)

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls REGISTRY=$work/registry
  export PATH=$STUBS:$PATH PUBLISH_LIB=$SCRIPTS/publish/lib.sh
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags"
  : >"$CALLS"
  unset CRANE_DENIED
}

# tag DIGEST: sets the release tag of 1.2.3 at DIGEST.
tag() { "$SCRIPTS/publish/tag.sh" "$repo" 1.2.3 "$1"; }

# pushed: pushes the list of a release 1.2.3 by digest, as publish-index does;
# prints its digest.
pushed() {
  pushed_platforms "$amd64" "$arm64"
  "$SCRIPTS/publish/index.sh" "$repo" 1.2.3 abc123 "$amd64" "$arm64" 2>/dev/null
}

setup
run "publish-tag: sets an absent release tag" ok tag "$list"
expect calls "tag v1.2.3 $list"
expect tag v1.2.3 "$list"
expect message "v1.2.3 now points at $list"
finish

setup
echo "$list" >"$REGISTRY/tags/v1.2.3"
run "publish-tag: a tag already at the digest is left alone" ok tag "$list"
expect calls ""
expect message "v1.2.3 already points at $list"
finish

setup
echo "$other" >"$REGISTRY/tags/v1.2.3"
run "publish-tag: refuses to move a release tag" fail tag "$list"
expect message "release tags are immutable"
expect calls ""
expect tag v1.2.3 "$other"
finish

setup
export CRANE_DENIED=1
run "publish-tag: fails when the tag cannot be read" fail tag "$list"
expect message "cannot read $repo:v1.2.3"
expect calls ""
finish

# A run that pushed the list and failed before the tag, such as on the
# attestation, is completed by a rerun.
setup
pushed >/dev/null
digest=$(pushed)
: >"$CALLS"
run "publish-tag: a rerun after a failure before the tag sets it" ok tag "$digest"
expect calls "tag v1.2.3 $digest"
finish

setup
run "publish-tag: rejects a malformed version" fail \
  "$SCRIPTS/publish/tag.sh" "$repo" 1.2 "$list"
expect calls ""
finish

setup
run "publish-tag: rejects a malformed digest" fail \
  "$SCRIPTS/publish/tag.sh" "$repo" 1.2.3 "${list:0:20}"
expect calls ""
finish

summary
