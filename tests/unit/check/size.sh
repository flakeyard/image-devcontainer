# shellcheck shell=bash
# Tests of scripts/check/size.sh, with a stub of nix and a fake image stream.
# shellcheck disable=SC2154 # work comes from setup

# size_setup: a stream of the image of 3 MiB on x86_64-linux.
size_setup() {
  stubbed_setup
  apply STREAM="$work/stream" SYSTEM=x86_64-linux IMAGE_LIB="$code_root/scripts/lib/image.sh"
  cat >"$work/stream" <<STREAM
#!$(command -v bash)
head -c 3145728 /dev/zero
STREAM
  chmod +x "$work/stream"
}

size_setup
printf '# comment\nx86_64-linux 3\naarch64-linux 1\n' >"$work/budget"
run "size: within the budget" ok scripts/check/size.sh -- "$work/budget"
expect message "is 3 MiB (3145728 bytes); its budget is 3 MiB"
finish

size_setup
printf 'x86_64-linux 2\n' >"$work/budget"
run "size: over the budget" fail scripts/check/size.sh -- "$work/budget"
expect message "exceeds its budget"
finish

size_setup
apply SYSTEM=aarch64-linux
printf 'x86_64-linux 3\n' >"$work/budget"
run "size: no budget for the system" fail scripts/check/size.sh -- "$work/budget"
expect message "no budget for aarch64-linux"
finish
