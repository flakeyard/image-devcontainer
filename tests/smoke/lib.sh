# shellcheck shell=bash
# Harness of the smoke tests: runs the loaded image with docker on the runner.
# Every test is named; a failure prints its output and the suite continues.
# Inputs (environment): IMAGE, the loaded image.

failed=0 passed=0 current="" output=""

# Scripts that tests run in a container, as `sh -s <"$probes/NAME.sh"`.
# shellcheck disable=SC2034 # used by the tests
probes=$(dirname -- "${BASH_SOURCE[0]}")/probes
# The fixtures of tests/fixture, as an absolute path that docker can mount.
# shellcheck disable=SC2034 # used by the tests
fixtures=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../fixture" && pwd)
# Seconds a new container has to get ready: its command runs and its Nix
# daemon answers.
daemon_timeout=20
# The capabilities the README documents as required.
documented_caps=(CHOWN DAC_OVERRIDE FOWNER SETUID SETGID)
# Docker arguments that leave a container only the documented capabilities.
# shellcheck disable=SC2034 # used by the tests
only_documented_caps=(--cap-drop ALL "${documented_caps[@]/#/--cap-add=}")
# The uid of a build user.
build_uid='300[0-9][0-9]'

# suite FILE...: runs the files of tests at the same time, each in a subshell
# with its own output, then prints the outputs in the order of the files and
# the sum of their counts. The files share no state but the image and the
# scratch directory, where each uses paths of its own.
suite() {
  local files=("$@") results index pids=()
  results=$(mktemp -d)
  for index in "${!files[@]}"; do
    run_file "${files[index]}" "$results/$index" >"$results/$index.log" 2>&1 &
    pids+=("$!")
  done
  for index in "${!files[@]}"; do
    wait "${pids[index]}" || true
    report_file "${files[index]}" "$results/$index"
  done
  rm -rf -- "$results"
  summary
}

# run_file FILE COUNTS: runs the tests of FILE and writes the numbers of
# passed and failed tests to COUNTS. errexit is off in them: a command that
# would end the script under errexit fails the current test instead, and the
# file goes on.
run_file() {
  local file=$1 counts=$2
  set +e
  trap 'failed_command "$?" "$BASH_COMMAND"' ERR
  # shellcheck disable=SC1090 # the tests come from the argument
  source "$file"
  trap - ERR
  finish
  printf '%s %s\n' "$passed" "$failed" >"$counts"
}

# report_file FILE RESULT: prints the output of the tests of FILE from
# RESULT.log and adds the counts of RESULT to those of the suite. A file
# that ended before it wrote its counts fails.
report_file() {
  local file=$1 result=$2 file_passed file_failed
  printf '== %s\n' "${file##*/}"
  cat -- "$result.log"
  if ! read -r file_passed file_failed 2>/dev/null <"$result"; then
    printf 'FAIL %s: ended before its last test\n' "${file##*/}"
    file_passed=0 file_failed=1
  fi
  passed=$((passed + file_passed)) failed=$((failed + file_failed))
}

# failed_command STATUS COMMAND: fails the test with the first line of COMMAND.
failed_command() {
  local status=$1 command=$2
  fail "exit $status of: ${command%%$'\n'*}"
}

# test_case NAME: starts a test.
test_case() {
  finish
  current=$1
}

fail() {
  [[ -n $current ]] || return 0
  printf 'FAIL %s: %s\n' "$current" "$1"
  [[ -z $output ]] || printf '%s\n' "$output" | sed 's/^/    /' | tail -n 20
  failed=$((failed + 1))
  current=""
}

finish() {
  if [[ -n $current ]]; then
    printf 'ok   %s\n' "$current"
    passed=$((passed + 1))
  fi
  current="" output=""
}

# run DOCKER_ARGS... -- COMMAND...: runs a container of the image to completion;
# output holds stdout and stderr.
run() {
  local args=()
  while (($#)) && [[ $1 != -- ]]; do
    args+=("$1")
    shift
  done
  shift
  # The exit status is not checked: tests check the output, and some expect
  # the container to fail.
  output=$(timeout 120 docker run --rm "${args[@]}" "$IMAGE" "$@" 2>&1) || true
}

# expect_line LINE: output has the line.
expect_line() { grep -qxF -- "$1" <<<"$output" || fail "no line '$1'"; }
# expect_text TEXT: output contains the text.
expect_text() { grep -qF -- "$1" <<<"$output" || fail "no '$1'"; }
expect_no_text() { ! grep -qF -- "$1" <<<"$output" || fail "unexpected '$1'"; }
# build_fixture DOCKER_ARGS...: builds the fixture uid.nix and reads the
# result in the same container; output holds the uid that built it.
build_fixture() {
  # shellcheck disable=SC2016 # the command runs in the container
  run "$@" -v "$fixtures:/fixture:ro" -- sh -c 'cat "$(nix-build --no-out-link /fixture/uid.nix)"'
}

# expect_build_user: output is the uid of a build user.
expect_build_user() { grep -qxE -- "$build_uid" <<<"$output" || fail "not built as a build user"; }

# poll SECONDS COMMAND...: retries COMMAND every 0.2 s until it succeeds.
poll() {
  local deadline=$((SECONDS + $1))
  shift
  until "$@"; do
    ((SECONDS < deadline)) || return 1
    sleep 0.2
  done
}

# start DOCKER_ARGS...: starts a detached container; prints its id.
start() { docker run -d "$@" "$IMAGE"; }

# ready ID: the command of the container runs and its Nix daemon answers;
# output holds the uid of the command. The daemon answers before the
# entrypoint execs tini, which then starts the command. The kernel drops a
# SIGTERM that reaches PID 1 during that exec, before tini handles signals:
# a container stopped then waits 10 s for the SIGKILL of docker stop.
ready() {
  local id=$1
  command_uid "$id" && docker exec -u dev "$id" nix store info >/dev/null 2>&1
}

# command_uid ID: output is the uid of the command of the container.
command_uid() {
  local id=$1
  output=$(docker exec -i "$id" sh -s <"$probes/command-uid.sh" 2>/dev/null)
  # Processes may end while the loop reads /proc: wait for the uid itself.
  [[ $output =~ ^[0-9]+$ ]]
}

# start_ready VARIABLE DOCKER_ARGS...: starts a detached container, sets
# VARIABLE to its id, and fails the test unless it is ready. A variable rather
# than stdout, because fail does not count in a subshell.
start_ready() {
  local variable=$1 started
  shift
  printf -v "$variable" '%s' ""
  started=$(start "$@") || return
  printf -v "$variable" '%s' "$started"
  poll "$daemon_timeout" ready "$started" || fail "the command or the daemon did not start"
}

# remove ID: removes the container, if one was started.
remove() {
  local id=$1
  [[ -z $id ]] || docker rm -f "$id" >/dev/null
}

# collect_garbage ID: collects the garbage of the store of the container.
collect_garbage() {
  local id=$1
  docker exec "$id" nix-collect-garbage >/dev/null 2>&1 || fail "garbage collection failed"
}

summary() {
  finish
  echo "passed: $passed, failed: $failed"
  ((failed == 0))
}
