# shellcheck shell=bash
# Enters the project shell of the working directory with nix and with direnv,
# and prints a variable it sets. The script comes on stdin: nix and direnv
# must not read it.
nix print-dev-env --print-build-logs >/dev/null </dev/null && echo print-dev-env-ok
# shellcheck disable=SC2016 # expanded in the project shell
direnv allow . </dev/null && direnv exec . sh -c 'echo "variable: $FIXTURE_VARIABLE"' </dev/null
