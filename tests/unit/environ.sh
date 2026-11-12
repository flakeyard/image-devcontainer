#!/usr/bin/env bash
# Unit tests of environ (entrypoint/environ.c), the built program. The harness
# is that of the shell library.
#
# Inputs (environment): ENVIRON, the built program; SHELL_LIB, the shell
# library.
# shellcheck disable=SC2016,SC2034,SC2154 # the programs it writes; code_root is read, work and env_vars set by the harness
set -uo pipefail
export LC_ALL=C

testing=${SHELL_LIB:?the tests need SHELL_LIB, the directory of the shell library}/internal/testing
# shellcheck source=/dev/null
source "$testing/case.sh"
# shellcheck source=/dev/null
source "$testing/checks.sh"

code_root=${ENVIRON:?the tests need ENVIRON, the built environ}
# The tools of the tests, for the PATH that from-fd searches.
tools=$(dirname -- "$(command -v env)")
bash_path=$(command -v bash)

# program NAME TEXT: writes the executable file $work/NAME with TEXT.
program() {
  local name=$1 text=$2
  printf '%s\n' "$text" >"$work/$name"
  chmod +x "$work/$name"
}

# entries ENTRY...: writes the ENTRYs, each ended by a NUL, to
# $work/environment, which the tests open as descriptor 3.
entries() { printf '%s\0' "$@" >"$work/environment"; }

# from_fd ARG...: runs environ from-fd 3 ARG... with only the variables of
# $work/environment, open as descriptor 3; sets status, and writes stdout and
# stderr to $work/stdout and $work/stderr.
from_fd() {
  status=0
  env -i "$code_root/bin/environ" from-fd 3 "$@" 3<"$work/environment" >"$work/stdout" 2>"$work/stderr" ||
    status=$?
}

# expect_status STATUS: the last from_fd exited with STATUS.
expect_status() {
  local expected=$1
  [[ -z $current || $status == "$expected" ]] || report "status $status, expected $expected: $(cat -- "$work/stderr")"
}

setup
# Prints its arguments after the first, the entries that the descriptor of
# the first reads, then HOME, which the harness sets, or "unset". It has no
# PATH: tr is named by its path.
program arguments "#!$bash_path
printf '%s\n' \"\${@:2}\"
$(command -v tr) '\\0' '\\n' <&\"\$1\"
printf '%s\n' \"\${HOME-unset}\""
run "to-fd passes the environment through a descriptor" ok bin/environ \
  A=1 "B=two words" -- to-fd "$work/arguments" first
expect stdout "$(printf '%s\n' first "${env_vars[@]}" A=1 "B=two words" unset)"
finish

setup
program arguments "#!$bash_path"
run "to-fd does not search PATH" fail bin/environ -- to-fd arguments
expect message "environ: arguments:"
finish

setup
entries A=1 "B=two words" HOME=/root "" NAME-ONLY PATH=/nowhere
run "from-fd runs the command with the variables, its own in place of theirs" ok bin/environ \
  -- from-fd 3 env 3<"$work/environment"
expect stdout "$(printf '%s\n' A=1 "B=two words" "" NAME-ONLY "${env_vars[@]}")"
finish

setup
entries A=1
run "from-fd closes the descriptor" ok bin/environ -- from-fd 3 "$bash_path" -c '[[ ! -e /dev/fd/3 ]]' \
  3<"$work/environment"
finish

setup
current="from-fd runs a file without #! with the shell, from the PATH of the variables"
entries "PATH=/nowhere:$work" A=1
program script 'echo "ran $0 $1 $A"'
from_fd script word
expect_status 0
expect stdout "ran $work/script word 1"
finish

setup
current="from-fd fails with 126 for a file it finds but cannot run"
entries "PATH=/nowhere:$work"
program script "#!$bash_path"
chmod -x "$work/script"
from_fd script
expect_status 126
expect message "environ: script: Permission denied"
finish

setup
current="from-fd fails with 127 for a command it does not find"
entries PATH=/nowhere
from_fd env
expect_status 127
expect message "environ: env: No such file or directory"
finish

# Not a number, standard streams, signed, too large, and no command.
for arguments in "x env" "0 env" "2 env" "-3 env" "+3 env" "99999999999999999999 env" "3"; do
  setup
  # shellcheck disable=SC2086 # the words of the case
  run "from-fd rejects '$arguments'" fail bin/environ -- from-fd $arguments
  expect message "usage: environ"
  finish
done

setup
run "from-fd fails on a closed descriptor" fail bin/environ -- from-fd 99 env
expect message "environ: 99: Bad file descriptor"
finish

setup
run "rejects an unknown mode" fail bin/environ -- into-fd env
expect message "usage: environ"
finish

conclude
