# shellcheck shell=bash
# Tests of scripts/publish/index.sh, with stubs of crane and regctl and a
# registry in a directory.
# shellcheck disable=SC2154 # work and registry come from setup

repo=ghcr.io/flakeyard/image-devcontainer
amd64=$(digest_of a)
arm64=$(digest_of b)

# index_setup: the platform manifests of a release, pushed by digest.
index_setup() {
  stubbed_setup
  apply PUBLISH_LIB="$code_root/scripts/publish/lib.sh"
  pushed_platforms "$amd64" "$arm64"
}

# publish NAME EXPECTED: test NAME publishes the list of 1.2.3; EXPECTED is ok
# or fail.
publish() {
  local name=$1 expected=$2
  run "publish-index: $name" "$expected" scripts/publish/index.sh -- "$repo" 1.2.3 abc123 "$amd64" "$arm64"
}

index_setup
publish "pushes the list by digest without a tag" ok
digest=$(<"$work/stdout")
expect_calls "put $digest"
expect_tag v1.2.3 ""
if [[ -n $current ]]; then
  jq -e '.manifests[0].platform.architecture == "amd64" and .manifests[1].platform.architecture == "arm64"
    and .annotations["org.opencontainers.image.version"] == "1.2.3"
    and .annotations["org.opencontainers.image.revision"] == "abc123"' \
    "$registry/manifests/$digest" >/dev/null || report "index: $(cat "$registry/manifests/$digest")"
fi
finish

# The digest of the canonical JSON of the list for the inputs of publish: a
# change of its bytes changes the digest consumers pin.
index_setup
publish "the exact bytes of the list" ok
pinned=sha256:2268211f761ccdcc84ce34b5d106de9887490dffe29561f97410bdb00fd75fbb
if [[ -n $current && $(<"$work/stdout") != "$pinned" ]]; then
  report "digest $(<"$work/stdout"), not $pinned: $(cat "$registry/manifests/$(<"$work/stdout")")"
fi
finish

index_setup
publish "the same release gives the same digest" ok
first=$(<"$work/stdout")
: >"$work/calls"
publish "a rerun changes no tag" ok
expect stdout "$first"
expect_calls "put $first"
finish

index_setup
digest_of c >"$registry/tags/v1.2.3"
publish "refuses to move a release tag" fail
expect message "release tags are immutable"
expect no-calls
finish

index_setup
apply CRANE_DENIED=1
publish "fails when the tag cannot be read" fail
expect message "cannot read $repo:v1.2.3"
expect no-calls
finish

index_setup
rm "$registry/manifests/$arm64"
publish "needs both platform manifests in the registry" fail
expect no-calls
finish

index_setup
publish "descriptor sizes are the bytes of the manifests" ok
if [[ -n $current ]]; then
  size=$(wc -c <"$registry/manifests/$amd64")
  jq -e --argjson s "$size" '.manifests[0].size == $s' "$registry/manifests/$(<"$work/stdout")" >/dev/null \
    || report "size is not $size"
fi
finish

index_setup
printf '%s' '{"mediaType":"application/vnd.oci.image.index.v1+json"}' >"$registry/manifests/$arm64"
publish "a platform must be an image manifest" fail
expect message "is not an image manifest"
expect no-calls
finish

index_setup
publish "first run" ok
digest=$(<"$work/stdout")
echo "$digest" >"$registry/tags/v1.2.3"
: >"$work/calls"
publish "a tag already at the digest is left alone" ok
expect_calls "put $digest"
finish

index_setup
run "publish-index: rejects a malformed version" fail \
  scripts/publish/index.sh -- "$repo" 1.2 abc "$amd64" "$arm64"
expect no-calls
finish
