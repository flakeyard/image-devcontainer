# shellcheck shell=bash
# Tests of scripts/publish/verify.sh, with stubs of crane, regctl, docker and
# gh and a registry in a directory. The release is published with
# scripts/publish/index.sh and scripts/publish/tag.sh.
# shellcheck disable=SC2154 # work comes from setup

repo=ghcr.io/flakeyard/image-devcontainer
amd64=$(digest_of a)
arm64=$(digest_of b)
revision=abc123 other=def456

# verify_setup: the platform manifests of a release, pushed by digest.
verify_setup() {
  stubbed_setup
  apply PUBLISH_LIB="$code_root/scripts/publish/lib.sh"
  pushed_platforms "$amd64" "$arm64"
}

# published: a release 1.2.3 as publish-index and publish-tag leave it;
# prints its digest.
published() {
  local digest
  digest=$(with_test_env "$code_root/scripts/publish/index.sh" "$repo" 1.2.3 "$revision" "$amd64" "$arm64" 2>/dev/null)
  with_test_env "$code_root/scripts/publish/tag.sh" "$repo" 1.2.3 "$digest" >/dev/null 2>&1
  echo "$digest"
}

# verify NAME EXPECTED PLATFORM: test NAME verifies the release with the
# tested digest PLATFORM for amd64; EXPECTED is ok or fail.
verify() {
  local name=$1 expected=$2 platform=$3
  run "publish-verify: $name" "$expected" scripts/publish/verify.sh -- \
    flakeyard/image-devcontainer "$repo" "$index" 1.2.3 "$revision" amd64 "$platform"
}

# git_tag_at COMMIT: the API has the git tag v1.2.3 at COMMIT.
git_tag_at() {
  local commit=$1
  fixture repos/flakeyard/image-devcontainer/commits/tags/v1.2.3 "{\"sha\": \"$commit\"}"
}

# attested_at COMMIT: the attestations are of COMMIT.
attested_at() {
  local commit=$1
  apply ATTESTED=1 ATTESTED_COMMIT="$commit"
}

verify_setup
index=$(published)
git_tag_at "$revision"
attested_at "$revision"
verify "a complete release" ok "$amd64"
expect message "Verified $repo:v1.2.3@$index on amd64"
expect call "--signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml"
expect call "verify oci://$repo@$index --repo flakeyard/image-devcontainer --signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml --deny-self-hosted-runners --source-digest $revision"
expect no-call "verify oci://$repo@$amd64 --repo flakeyard/image-devcontainer --signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml --deny-self-hosted-runners --source-digest"
finish

verify_setup
index=$(published)
git_tag_at "$revision"
attested_at "$revision"
verify "another tested digest" fail "$arm64"
expect message "was tested"
finish

verify_setup
index=$(published)
digest_of d >"$registry/tags/v1.2.3"
git_tag_at "$revision"
attested_at "$revision"
verify "the release tag points elsewhere" fail "$amd64"
expect message "not at $index"
finish

verify_setup
index=$(published)
git_tag_at "$revision"
verify "missing attestations" fail "$amd64"
finish

verify_setup
index=$(published)
git_tag_at "$revision"
attested_at "$other"
verify "the list is attested for another commit" fail "$amd64"
expect message "another commit"
finish

verify_setup
index=$(published)
git_tag_at "$other"
attested_at "$revision"
verify "the git tag is at another commit" fail "$amd64"
expect message "the git tag v1.2.3 is at $other, not at $revision"
finish

verify_setup
index=$(published)
attested_at "$revision"
verify "no git tag" fail "$amd64"
expect message "cannot read the git tag v1.2.3"
finish
