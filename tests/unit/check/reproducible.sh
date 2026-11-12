# shellcheck shell=bash
# Tests of scripts/check/reproducible.sh, with stubs of nix and nix-store and
# a fake image stream.
# shellcheck disable=SC2154 # work comes from setup

# reproducible_setup: a stream of the image, which differs on every run with
# $work/vary, and the derivations of the image: the stream needs a layer and
# glibc, which needs a bootstrap tool; the layer needs a source, a
# fixed-output derivation, which has no path. The cache lacks the stream, the
# layer and the bootstrap tool, which is not needed, because the cache has
# glibc.
reproducible_setup() {
  stubbed_setup
  apply STREAM="$work/stream" IMAGE_LIB="$code_root/scripts/lib/image.sh" \
    DERIVATION=/nix/store/aaaa-stream.drv DERIVATIONS="$work/derivations.json" \
    UNCACHED="/nix/store/aaaa-stream /nix/store/bbbb-layer /nix/store/eeee-bootstrap"
  cat >"$work/stream" <<STREAM
#!$(command -v bash)
echo image
if [[ -e $work/vary ]]; then echo "\$SRANDOM"; fi
STREAM
  chmod +x "$work/stream"
  cat >"$work/derivations.json" <<'DERIVATIONS'
{
  "version": 4,
  "derivations": {
    "aaaa-stream.drv": {
      "outputs": { "out": { "path": "aaaa-stream" } },
      "inputs": { "drvs": { "bbbb-layer.drv": {}, "cccc-glibc.drv": {} } }
    },
    "bbbb-layer.drv": {
      "outputs": { "out": { "path": "bbbb-layer" } },
      "inputs": { "drvs": { "cccc-glibc.drv": {}, "ffff-source.drv": {} } }
    },
    "ffff-source.drv": {
      "outputs": { "out": { "hash": "sha256-AAAA", "method": "nar" } },
      "inputs": { "drvs": {} }
    },
    "cccc-glibc.drv": {
      "outputs": { "out": { "path": "cccc-glibc" }, "dev": { "path": "cccc-glibc-dev" } },
      "inputs": { "drvs": { "eeee-bootstrap.drv": {} } }
    },
    "eeee-bootstrap.drv": {
      "outputs": { "out": { "path": "eeee-bootstrap" } },
      "inputs": { "drvs": {} }
    }
  }
}
DERIVATIONS
}

reproducible_setup
run "reproducible: rebuilds the derivations that the cache lacks" ok scripts/check/reproducible.sh
expect_calls "build;rebuild --no-link --rebuild --keep-going /nix/store/aaaa-stream.drv^* /nix/store/bbbb-layer.drv^*"
expect message "Rebuilding /nix/store/bbbb-layer.drv"
expect message "needs 2 derivations"
expect message "Two streams of the image are equal"
finish

# The local store has built everything; the cache decides all the same.
reproducible_setup
apply UNCACHED=""
run "reproducible: nothing to rebuild fails" fail scripts/check/reproducible.sh
expect message "found no derivation of the image to rebuild"
finish

reproducible_setup
apply CACHE_ERROR="error: unable to download 'https://cache.nixos.org/nix-cache-info'"
run "reproducible: a failing query of the cache fails" fail scripts/check/reproducible.sh
expect message "unable to download"
finish

reproducible_setup
apply REBUILD_ERROR="error: derivation '/nix/store/bbbb-layer.drv' may not be deterministic"
run "reproducible: a rebuild that differs fails" fail scripts/check/reproducible.sh
expect message "bbbb-layer.drv' may not be deterministic"
finish

reproducible_setup
touch "$work/vary"
run "reproducible: different streams fail" fail scripts/check/reproducible.sh
expect message "two streams of the image differ"
finish
