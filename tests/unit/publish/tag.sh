# shellcheck shell=bash
# Tests of scripts/publish/tag.sh, with stubs of crane and regctl and a
# registry in a directory.
# shellcheck disable=SC2154 # work and registry come from setup

repo=ghcr.io/flakeyard/image-devcontainer
amd64=$(digest_of a)
arm64=$(digest_of b)
list=$(digest_of d)
other=$(digest_of c)

tag_setup() {
  stubbed_setup
  apply PUBLISH_LIB="$code_root/scripts/publish/lib.sh"
}

# tag NAME EXPECTED DIGEST: test NAME sets the release tag of 1.2.3 at
# DIGEST; EXPECTED is ok or fail.
tag() {
  local name=$1 expected=$2 digest=$3
  run "publish-tag: $name" "$expected" scripts/publish/tag.sh -- "$repo" 1.2.3 "$digest"
}

# pushed: pushes the list of a release 1.2.3 by digest, as publish-index does;
# prints its digest.
pushed() {
  pushed_platforms "$amd64" "$arm64"
  with_test_env "$code_root/scripts/publish/index.sh" "$repo" 1.2.3 abc123 "$amd64" "$arm64" 2>/dev/null
}

tag_setup
tag "sets an absent release tag" ok "$list"
expect_calls "tag v1.2.3 $list"
expect_tag v1.2.3 "$list"
expect message "v1.2.3 now points at $list"
finish

tag_setup
echo "$list" >"$registry/tags/v1.2.3"
tag "a tag already at the digest is left alone" ok "$list"
expect no-calls
expect message "v1.2.3 already points at $list"
finish

tag_setup
echo "$other" >"$registry/tags/v1.2.3"
tag "refuses to move a release tag" fail "$list"
expect message "release tags are immutable"
expect no-calls
expect_tag v1.2.3 "$other"
finish

tag_setup
apply CRANE_DENIED=1
tag "fails when the tag cannot be read" fail "$list"
expect message "cannot read $repo:v1.2.3"
expect no-calls
finish

# A run that pushed the list and failed before the tag, such as on the
# attestation, is completed by a rerun.
tag_setup
pushed >/dev/null
digest=$(pushed)
: >"$work/calls"
tag "a rerun after a failure before the tag sets it" ok "$digest"
expect_calls "tag v1.2.3 $digest"
finish

tag_setup
run "publish-tag: rejects a malformed version" fail \
  scripts/publish/tag.sh -- "$repo" 1.2 "$list"
expect no-calls
finish

tag_setup
run "publish-tag: rejects a malformed digest" fail \
  scripts/publish/tag.sh -- "$repo" 1.2.3 "${list:0:20}"
expect no-calls
finish
