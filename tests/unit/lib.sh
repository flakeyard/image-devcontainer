# shellcheck shell=bash disable=SC2154 # work comes from the setup of the suite
# Harness of the unit tests, sourced by every suite. A case is
#
#   setup; run NAME EXPECTED COMMAND...; expect KIND ARGS...; finish
#
# where the suite's setup makes $work, the directory of the case, and exports
# CALLS and REGISTRY where its stubs use them. The first failure of a case
# reports it; later expectations of the case are skipped. A suite ends with
# summary, which gives its exit status.

failed=0 passed=0 current=""

# begin NAME: starts the case NAME, for a case that runs no single command.
begin() { current=$1; }

# still_passing: whether a case is running and has not failed yet.
still_passing() { [[ -n $current ]]; }

# report MESSAGE: fails the current case, once.
report() {
  local message=$1
  still_passing || return 0
  printf 'FAIL %s: %s\n' "$current" "$message"
  failed=$((failed + 1))
  current=""
}

# printed: the stdout of the command of the case.
printed() { cat -- "$work/out"; }

# captured: everything the command of the case wrote, stdout first.
captured() { cat -- "$work/out" "$work/err"; }

# run NAME EXPECTED COMMAND...: starts the case NAME and runs COMMAND, its
# stdout to $work/out and its stderr to $work/err. EXPECTED is its outcome.
run() {
  local name=$1 expected=$2 status=0
  shift 2
  begin "$name"
  # Without a command, the case would pass without testing anything.
  (($#)) || {
    report "no command to run"
    return
  }
  "$@" >"$work/out" 2>"$work/err" || status=$?
  outcome "$expected" "$status"
}

# outcome EXPECTED STATUS: fails the case unless the exit status STATUS is the
# EXPECTED outcome: ok (zero), fail (non-zero) or any.
outcome() {
  local expected=$1 status=$2
  case $expected in
    ok) ((status == 0)) ;;
    fail) ((status != 0)) ;;
    any) true ;;
    *) false ;;
  esac || report "expected $expected, exit $status: $(captured)"
}

# expect KIND ARGS...: an expectation of the current case:
#   message TEXT     stdout or stderr contains TEXT
#   output TEXT      stdout is TEXT
#   calls TEXT       the stub calls, joined by ';', are TEXT
#   called TEXT      a stub call contains TEXT
#   not_called TEXT  no stub call contains TEXT
#   line FILE LINE   FILE has the line LINE
#   empty FILE       FILE is empty or missing
#   tag TAG DIGEST   the tag TAG of the registry points at DIGEST
expect() {
  local kind=$1
  shift
  still_passing || return 0
  case $kind in
    message | output | calls | called | not_called | line | empty | tag) "expect_$kind" "$@" ;;
    *) report "unknown expectation '$kind'" ;;
  esac
}

expect_message() {
  local text=$1
  grep -qF -- "$text" "$work/out" "$work/err" || report "no message '$text' in: $(captured)"
}

expect_output() {
  local text=$1
  [[ $(printed) == "$text" ]] || report "printed '$(printed)', expected '$text'; stderr: $(cat -- "$work/err")"
}

# joined_calls: the stub calls on one line, separated by ';'.
joined_calls() { paste -sd';' "$CALLS"; }

expect_calls() {
  local text=$1
  [[ $(joined_calls) == "$text" ]] || report "calls '$(joined_calls)', expected '$text'"
}

expect_called() {
  local text=$1
  grep -qF -- "$text" "$CALLS" || report "no call with '$text' in: $(cat -- "$CALLS")"
}

expect_not_called() {
  local text=$1
  ! grep -qF -- "$text" "$CALLS" || report "a call with '$text' in: $(cat -- "$CALLS")"
}

expect_line() {
  local file=$1 line=$2
  grep -qxF -- "$line" "$file" || report "no line '$line' in $file: $(cat -- "$file")"
}

expect_empty() {
  local file=$1
  [[ ! -s $file ]] || report "$file is not empty: $(cat -- "$file")"
}

# tagged TAG: the digest the tag TAG of the registry points at.
tagged() {
  local tag=$1
  cat -- "$REGISTRY/tags/$tag" 2>/dev/null
}

expect_tag() {
  local tag=$1 digest=$2
  [[ $(tagged "$tag") == "$digest" ]] || report "tag $tag is '$(tagged "$tag")', expected '$digest'"
}

# finish: counts the case as passed unless it failed, runs the suite's
# on_finish hook if it has one, and removes $work.
finish() {
  if still_passing; then passed=$((passed + 1)); fi
  current=""
  if declare -F on_finish >/dev/null; then on_finish; fi
  rm -rf -- "$work"
}

# summary: prints the tally of the suite; fails when a case failed.
summary() {
  echo "passed: $passed, failed: $failed"
  ((failed == 0))
}
