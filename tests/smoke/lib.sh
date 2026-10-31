# shellcheck shell=bash
# Harness of the smoke tests: runs the loaded image with docker on the runner.
# Every test is named; a failure prints its output and the suite continues.
# Inputs (environment): IMAGE, the loaded image.

failed=0 passed=0 current="" output=""

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

summary() {
  finish
  echo "passed: $passed, failed: $failed"
  ((failed == 0))
}
