# shellcheck shell=bash
# The state of the stubs in tests/bin for one test. Source this file after
# case.sh of the shell library.
# shellcheck disable=SC2154 # code_root comes from tests/run.sh

# stubbed_setup: setup of the library, with the stubs of tests/bin before
# those of the library on PATH and SHELL_LIB for the gh stub.
stubbed_setup() {
  setup
  apply PATH="$code_root/tests/bin:$TESTING_BIN:$HOST_PATH" SHELL_LIB="$SHELL_LIB"
}
