# shellcheck shell=bash
# Tests of scripts/check/reproducible.sh, with a stub of nix and a fake image
# stream.
# shellcheck disable=SC2154 # work comes from setup

# reproducible_setup: a stream of the image, which differs on every run with
# $work/vary, and a plan that builds two derivations.
reproducible_setup() {
  stubbed_setup
  apply STREAM="$work/stream" IMAGE_LIB="$code_root/scripts/lib/image.sh"
  cat >"$work/stream" <<STREAM
#!$(command -v bash)
echo image
if [[ -e $work/vary ]]; then echo "\$SRANDOM"; fi
STREAM
  chmod +x "$work/stream"
  apply DRY_RUN="these 2 derivations will be built:
  /nix/store/aaaa-entrypoint.drv
  /nix/store/bbbb-stream.drv
these 300 paths will be fetched (100.00 MiB download, 400.00 MiB unpacked):
  /nix/store/cccc-glibc"
}

reproducible_setup
run "reproducible: rebuilds the own derivations" ok scripts/check/reproducible.sh
expect_calls "build;rebuild --no-link --rebuild --keep-going /nix/store/aaaa-entrypoint.drv^* /nix/store/bbbb-stream.drv^*"
expect message "Rebuilding /nix/store/bbbb-stream.drv"
expect message "needs 2 derivations"
expect message "Two streams of the image are equal"
finish

reproducible_setup
apply DRY_RUN="these 300 paths will be fetched (1.00 MiB download, 4.00 MiB unpacked):
  /nix/store/cccc-glibc"
run "reproducible: nothing to rebuild" ok scripts/check/reproducible.sh
expect_calls "build"
expect message "needs 0 derivations"
finish

reproducible_setup
apply REBUILD_ERROR="error: derivation '/nix/store/bbbb-stream.drv' may not be deterministic"
run "reproducible: a rebuild that differs fails" fail scripts/check/reproducible.sh
expect message "bbbb-stream.drv' may not be deterministic"
finish

reproducible_setup
touch "$work/vary"
run "reproducible: different streams fail" fail scripts/check/reproducible.sh
expect message "two streams of the image differ"
finish
