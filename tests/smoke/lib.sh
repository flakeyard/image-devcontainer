# shellcheck shell=bash
# Harness of the smoke tests: runs the loaded image with docker on the runner.
# Every test is named; a failure prints its output and the suite continues.
# Inputs (environment): IMAGE, the loaded image.

failed=0 passed=0 current="" output=""

# Seconds the Nix daemon of a new container has to answer.
daemon_timeout=20
# The capabilities the README documents as required.
documented_caps=(CHOWN DAC_OVERRIDE FOWNER SETUID SETGID)
# Docker arguments that leave a container only the documented capabilities.
# shellcheck disable=SC2034 # used by the tests
only_documented_caps=(--cap-drop ALL "${documented_caps[@]/#/--cap-add=}")
# The uid of a build user.
build_uid='300[0-9][0-9]'

# suite FILE...: runs the tests of the files. errexit is off in them: a command
# that would end the script under errexit fails the current test instead, and
# the suite goes on.
suite() {
  local file
  set +e
  trap 'failed_command "$?" "$BASH_COMMAND"' ERR
  for file; do
    # shellcheck disable=SC1090 # the tests come from the argument
    source "$file"
  done
  trap - ERR
  set -e
  summary
}

# failed_command STATUS COMMAND: fails the test with the first line of COMMAND.
failed_command() {
  local status=$1 command=$2
  fail "exit $status of: ${command%%$'\n'*}"
}

# test NAME: starts a test.
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

# ready ID: the Nix daemon in the container answers.
ready() { docker exec -u dev "$1" nix store info >/dev/null 2>&1; }

# start_ready VARIABLE DOCKER_ARGS...: starts a detached container, sets
# VARIABLE to its id, and fails the test unless its Nix daemon answers. A
# variable rather than stdout, because fail does not count in a subshell.
start_ready() {
  local variable=$1 started
  shift
  printf -v "$variable" '%s' ""
  started=$(start "$@") || return
  printf -v "$variable" '%s' "$started"
  poll "$daemon_timeout" ready "$started" || fail "the daemon did not answer"
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
