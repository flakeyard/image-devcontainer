#!/usr/bin/env bash
# Unit tests of environ (entrypoint/environ.c), the built program. The harness
# is that of the shell library.
#
# Inputs (environment): ENVIRON, the built program; SHELL_LIB, the shell
# library.
# shellcheck disable=SC2016,SC2034,SC2154 # the program it writes; code_root is read, work and env_vars set by the harness
set -uo pipefail
export LC_ALL=C

testing=${SHELL_LIB:?the tests need SHELL_LIB, the directory of the shell library}/internal/testing
# shellcheck source=/dev/null
source "$testing/case.sh"
# shellcheck source=/dev/null
source "$testing/checks.sh"

code_root=${ENVIRON:?the tests need ENVIRON, the built environ}
# The tools of the tests, for the PATH that from-args searches.
tools=$(dirname -- "$(command -v env)")

# arguments_program: writes a program to $work/arguments that prints its
# arguments, then its HOME, which the harness sets, or "unset".
arguments_program() {
  printf '#!%s\nprintf "%%s\\n" "$@" "${HOME-unset}"\n' "$(command -v bash)" >"$work/arguments"
  chmod +x "$work/arguments"
}

setup
arguments_program
run "to-args moves the environment in front of the arguments" ok bin/environ \
  -- to-args "$work/arguments" first "second word"
expect stdout "$(printf '%s\n' "${#env_vars[@]}" "${env_vars[@]}" first "second word" unset)"
finish

setup
arguments_program
run "to-args does not search PATH" fail bin/environ -- to-args arguments
expect message "environ: arguments:"
finish

setup
run "from-args runs the command with the variables only" ok bin/environ \
  -- from-args 3 A=1 "B=two words" "PATH=$tools" env
expect stdout "$(printf '%s\n' A=1 "B=two words" "PATH=$tools")"
finish

setup
run "from-args searches the PATH of the variables" fail bin/environ \
  -- from-args 1 PATH=/nowhere env
expect message "environ: env: No such file or directory"
finish

for arguments in "x env" "-1 env" "+1 A=1 env" "1 A=1" "2 A=1 env"; do
  setup
  # shellcheck disable=SC2086 # the words of the case
  run "from-args rejects '$arguments'" fail bin/environ -- from-args $arguments
  expect message "usage: environ"
  finish
done

setup
run "rejects an unknown mode" fail bin/environ -- into-args env
expect message "usage: environ"
finish

conclude
