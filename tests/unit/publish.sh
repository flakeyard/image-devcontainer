#!/usr/bin/env bash
# Unit tests of the publication scripts, with stubs of nix, crane and regctl
# and a registry in a directory. Inputs (environment): SCRIPTS, STUBS.
set -uo pipefail
export LC_ALL=C

failed=0 passed=0 current=""
repo=ghcr.io/flakeyard/image-devcontainer
amd64=sha256:$(printf 'a%.0s' {1..64})
arm64=sha256:$(printf 'b%.0s' {1..64})

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls REGISTRY=$work/registry STREAM=$work/stream
  export PATH=$STUBS:$PATH TARBALL_DIGEST=$amd64
  mkdir -p "$REGISTRY/manifests" "$REGISTRY/tags"
  : >"$CALLS"
  printf '#!%s\necho archive\n' "$(command -v bash)" >"$STREAM"
  chmod +x "$STREAM"
  unset CRANE_DENIED ATTESTED
  # The platform manifests of a release, pushed by digest.
  for digest in "$amd64" "$arm64"; do
    printf '%s' '{"mediaType":"application/vnd.docker.distribution.manifest.v2+json"}' >"$REGISTRY/manifests/$digest"
  done
}

run() {
  local name=$1 expected=$2 status=0
  shift 2
  "$@" >"$work/out" 2>"$work/err" || status=$?
  current=$name
  if [[ $expected == ok && $status != 0 ]] || [[ $expected == fail && $status == 0 ]]; then
    report "expected $expected, exit $status: $(cat "$work/out" "$work/err")"
  fi
}

report() {
  [[ -n $current ]] || return 0
  echo "FAIL $current: $1"
  failed=$((failed + 1))
  current=""
}

expect() {
  [[ -n $current ]] || return 0
  case $1 in
    message) grep -qF -- "$2" "$work/out" "$work/err" || report "no message '$2' in: $(cat "$work/out" "$work/err")" ;;
    calls) [[ $(paste -sd';' "$CALLS") == "$2" ]] || report "calls '$(paste -sd';' "$CALLS")', expected '$2'" ;;
    tag) [[ $(cat "$REGISTRY/tags/$2" 2>/dev/null) == "$3" ]] || report "tag $2 is '$(cat "$REGISTRY/tags/$2" 2>/dev/null)', expected '$3'" ;;
  esac
}

finish() {
  if [[ -n $current ]]; then passed=$((passed + 1)); fi
  current=""
  rm -rf -- "$work"
}

publish() { "$SCRIPTS/publish-index.sh" "$repo" 1.2.3 abc123 "$amd64" "$arm64"; }

# --- push-platform ---------------------------------------------------------------

setup
run "push-platform: pushes the tested digest" ok "$SCRIPTS/push-platform.sh" "$repo" "$amd64"
expect calls "push $amd64"
[[ -z $current || $(cat "$work/out") == "$amd64" ]] || report "printed $(cat "$work/out")"
finish

setup
run "push-platform: refuses another digest" fail "$SCRIPTS/push-platform.sh" "$repo" "$arm64"
expect message "but $arm64 was tested"
expect calls ""
finish

setup
run "push-platform: rejects a malformed digest" fail "$SCRIPTS/push-platform.sh" "$repo" latest
expect calls ""
finish

# --- publish-index -----------------------------------------------------------------

setup
run "publish-index: pushes the list by digest, then tags it" ok publish
digest=$(cat "$work/out")
expect calls "put $digest;tag v1.2.3 $digest"
expect tag v1.2.3 "$digest"
if [[ -n $current ]]; then
  jq -e '.manifests[0].platform.architecture == "amd64" and .manifests[1].platform.architecture == "arm64"
    and .annotations["org.opencontainers.image.version"] == "1.2.3"
    and .annotations["org.opencontainers.image.revision"] == "abc123"' \
    "$REGISTRY/manifests/$digest" >/dev/null || report "index: $(cat "$REGISTRY/manifests/$digest")"
fi
finish

setup
run "publish-index: the same release gives the same digest" ok publish
first=$(cat "$work/out")
: >"$CALLS"
run "publish-index: a rerun changes no tag" ok publish
[[ -z $current || $(cat "$work/out") == "$first" ]] || report "digest changed: $first, $(cat "$work/out")"
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
if [[ -n $current ]]; then
  size=$(wc -c <"$REGISTRY/manifests/$amd64")
  jq -e --argjson s "$size" '.manifests[0].size == $s' "$REGISTRY/manifests/$(cat "$work/out")" >/dev/null ||
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
digest=$(cat "$work/out")
rm "$REGISTRY/tags/v1.2.3" && echo "$digest" >"$REGISTRY/tags/v1.2.3"
: >"$CALLS"
run "publish-index: a tag already at the digest is left alone" ok publish
expect calls "put $digest"
finish

setup
run "publish-index: rejects a malformed version" fail \
  "$SCRIPTS/publish-index.sh" "$repo" 1.2 abc "$amd64" "$arm64"
expect calls ""
finish

# --- sync-major --------------------------------------------------------------------

setup
for version in 1.2.3 1.10.0 1.9.9 2.0.0; do
  echo "sha256:$(printf '%s' "$version" | sha256sum | cut -d' ' -f1)" >"$REGISTRY/tags/v$version"
done
newest=$(cat "$REGISTRY/tags/v1.10.0")
run "sync-major: points vX at the newest release of the major" ok "$SCRIPTS/sync-major.sh" "$repo" 1
expect tag v1 "$newest"
expect message "v1 now points at v1.10.0"
: >"$CALLS"
run "sync-major: a rerun changes nothing" ok "$SCRIPTS/sync-major.sh" "$repo" 1
expect calls ""
finish

setup
run "sync-major: fails without a release of the major" fail "$SCRIPTS/sync-major.sh" "$repo" 3
expect message "no release of major version 3"
finish

# --- verify-published -----------------------------------------------------------

# published: a release 1.2.3 as publish-index leaves it; prints its digest.
published() {
  "$SCRIPTS/publish-index.sh" "$repo" 1.2.3 abc123 "$amd64" "$arm64" 2>/dev/null
}
verify() {
  "$SCRIPTS/verify-published.sh" flakeyard/image-devcontainer "$repo" "$index" 1.2.3 abc123 amd64 "$1"
}

setup
index=$(published)
export ATTESTED=1
run "verify-published: a complete release" ok verify "$amd64"
expect message "Verified $repo:v1.2.3@$index on amd64"
[[ -z $current ]] || grep -qF -- "--source-digest abc123" "$CALLS" || report "calls: $(cat "$CALLS")"
finish

setup
index=$(published)
export ATTESTED=1
run "verify-published: another tested digest" fail verify "$arm64"
expect message "was tested"
finish

setup
index=$(published)
echo "sha256:$(printf 'd%.0s' {1..64})" >"$REGISTRY/tags/v1.2.3"
export ATTESTED=1
run "verify-published: the release tag points elsewhere" fail verify "$amd64"
expect message "not at $index"
finish

setup
index=$(published)
run "verify-published: missing attestations" fail verify "$amd64"
finish

echo "passed: $passed, failed: $failed"
((failed == 0))
