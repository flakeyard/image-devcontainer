# shellcheck shell=bash
# Static tests of .github/workflows/test.yaml: its jobs that run only on a
# schedule (workflow-check ADR-0003, FY-0032), and the pin of the shell
# library, whose tests nix flake check runs in the job image.
# shellcheck disable=SC2016 # jq, not expanded here

readonly TEST_DEFINITIONS='
  def on_schedule: "github.event_name == '"'schedule'"'";
  def scheduled: .if == "${{ \(on_schedule) }}";
  def scheduled_ids: [.jobs | to_entries[] | select(.value | scheduled) | .key];
  def may_skip: .jobs.check.with["caller-may-skip"] // "[]" | fromjson;
  def runs($app): any(.steps[]?.run // ""; contains(".#\($app) "));
'

if require_yq .github/workflows/test.yaml; then
  test_workflow=$(load_yaml .github/workflows/test.yaml)

  yaml_check "$test_workflow" "test workflow: jobs that run only on a schedule are checked and may be skipped" \
    "$TEST_DEFINITIONS"'.jobs.check.needs as $needs | may_skip as $skip | scheduled_ids
    | length > 0 and all(.[]; IN($needs[]) and IN($skip[]))'
  # caller-may-skip matches the names of the jobs without matrix values.
  yaml_check "$test_workflow" "test workflow: jobs that run only on a schedule have no name" \
    "$TEST_DEFINITIONS"'[.jobs[] | select(scheduled and has("name"))] == []'
  # A shared group would let a push cancel the weekly run while it waits.
  yaml_check "$test_workflow" "test workflow: the run on a schedule has its own concurrency group" \
    "$TEST_DEFINITIONS"'.concurrency.group | contains(on_schedule)'
  yaml_check "$test_workflow" "test workflow: the newest release is rebuilt on both architectures each week" \
    "$TEST_DEFINITIONS"'(.on.schedule | length > 0) and ([.jobs[] | select(scheduled and runs("check-release-rebuild"))
    | .strategy.matrix.include[].runner] | sort == ["ubuntu-24.04", "ubuntu-24.04-arm"])'
  # The repository uses the library only in tests, so the job that runs them
  # pins it (ADR-0001 of action-shell-lib).
  yaml_check "$test_workflow" "test workflow: the job image pins the shell library" \
    "$TEST_DEFINITIONS"'any(.jobs.image.steps[].uses // ""; startswith("flakeyard/action-shell-lib@"))'
  check_library_pins
fi
