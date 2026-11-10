# shellcheck shell=bash
# Tests of scripts/publish/platform.sh, with stubs of nix and crane and a
# registry in a directory.
# shellcheck disable=SC2154 # work comes from setup

repo=ghcr.io/flakeyard/image-devcontainer
amd64=$(digest_of a)
arm64=$(digest_of b)

# platform_setup: an image of the digest $amd64 and a stream of it.
platform_setup() {
  stubbed_setup
  apply STREAM="$work/stream" TARBALL_DIGEST="$amd64" PUBLISH_DIGEST="$code_root/scripts/publish/digest.sh"
  apply IMAGE_LIB="$code_root/scripts/lib/image.sh" PUBLISH_LIB="$code_root/scripts/publish/lib.sh"
  printf '#!%s\necho archive\n' "$(command -v bash)" >"$work/stream"
  chmod +x "$work/stream"
}

platform_setup
run "publish-platform: pushes the tested digest" ok scripts/publish/platform.sh -- "$repo" "$amd64"
expect_calls "push $amd64"
expect stdout "$amd64"
finish

platform_setup
run "publish-platform: refuses another digest" fail scripts/publish/platform.sh -- "$repo" "$arm64"
expect message "but $arm64 was tested"
expect no-calls
finish

platform_setup
# A publish-digest that records its flake.
cat >"$work/publish-digest" <<STUB
#!$(command -v bash)
echo "publish-digest \$2" >>"\$CALLS"
echo "\$TARBALL_DIGEST"
STUB
chmod +x "$work/publish-digest"
run "publish-platform: computes the digest with publish-digest" ok \
  scripts/publish/platform.sh PUBLISH_DIGEST="$work/publish-digest" -- "$repo" "$amd64" "$work/flake"
expect_calls "publish-digest $work/flake;push $amd64"
finish

platform_setup
run "publish-platform: rejects a malformed digest" fail scripts/publish/platform.sh -- "$repo" latest
expect no-calls
finish
