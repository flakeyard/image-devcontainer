#!/usr/bin/env bash
# Static tests of .github/workflows/test.yaml: its jobs that run only on a
# schedule (workflow-check ADR-0003, FY-0032). Inputs (environment): SCRIPTS,
# the .github directory.
# shellcheck disable=SC2016 # jq variables, not expanded here
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

workflow=$(yq -o=json . "$SCRIPTS/workflows/test.yaml") || exit 1

readonly definitions='
  def scheduled: .if == "${{ github.event_name == '"'schedule'"' }}";
  def scheduled_ids: [.jobs | to_entries[] | select(.value | scheduled) | .key];
  def may_skip: .jobs.check.with["caller-may-skip"] // "[]" | fromjson;
  def runs($app): any(.steps[]?.run // ""; contains(".#\($app) "));
'

setup() { work=$(mktemp -d); }

# holds FILTER: whether FILTER, after the definitions, is true of the workflow.
holds() {
  local filter=$1
  jq -e "$definitions $filter" <<<"$workflow" >/dev/null
}

setup
run "test workflow: jobs that run only on a schedule are checked and may be skipped" ok \
  holds '.jobs.check.needs as $needs | may_skip as $skip | scheduled_ids
    | length > 0 and all(.[]; IN($needs[]) and IN($skip[]))'
finish

# caller-may-skip matches the names of the jobs without matrix values.
setup
run "test workflow: jobs that run only on a schedule have no name" ok \
  holds '[.jobs[] | select(scheduled and has("name"))] == []'
finish

setup
run "test workflow: the newest release is rebuilt on both architectures each week" ok \
  holds '(.on.schedule | length > 0) and ([.jobs[] | select(scheduled and runs("check-release-rebuild"))
    | .strategy.matrix.include[].runner] | sort == ["ubuntu-24.04", "ubuntu-24.04-arm"])'
finish

summary
