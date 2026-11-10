# shellcheck shell=bash
# The state of the stubs in tests/bin for one test. Source this file after
# case.sh of the shell library.
# shellcheck disable=SC2154 # work and code_root come from the harness

# stubbed_setup: setup of the library, with the stubs of tests/bin before
# those of the library on PATH, SHELL_LIB for the gh stub, and an empty
# registry for the crane and regctl stubs in $registry.
stubbed_setup() {
  setup
  registry=$work/registry
  mkdir -p "$registry/manifests" "$registry/tags"
  apply PATH="$code_root/tests/bin:$TESTING_BIN:$HOST_PATH" SHELL_LIB="$SHELL_LIB" REGISTRY="$registry"
}

# digest_of CHARACTER: print the sha256 digest of 64 times CHARACTER.
digest_of() {
  local character=$1 hex
  printf -v hex '%64s' ''
  echo "sha256:${hex// /$character}"
}
