#!/usr/bin/env bash
# Static tests of .github/workflows/release.yaml: the environments of its jobs
# (FY-0027, FY-0030). A job publishes when it may write to the package or
# attest. Inputs (environment): SCRIPTS, the .github directory.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

workflow=$(yq -o=json . "$SCRIPTS/workflows/release.yaml") || exit 1

# shellcheck disable=SC2016 # jq variables
readonly definitions='
  def environment: .environment | if type == "object" then .name else . end;
  def publishes: (.permissions // {}) | [.packages, .attestations, ."id-token"] | any(. == "write");
  def publishing_jobs: [.jobs[] | select(publishes)];
  def jobs_in($name): [.jobs[] | select(environment == $name)];
'

setup() { work=$(mktemp -d); }

# holds FILTER: whether FILTER, after the definitions, is true of the workflow.
holds() {
  local filter=$1
  jq -e "$definitions $filter" <<<"$workflow" >/dev/null
}

setup
run "release workflow: every job that publishes runs in publish" ok \
  holds 'publishing_jobs | length > 0 and all(environment == "publish")'
finish

setup
run "release workflow: only jobs that publish run in publish" ok \
  holds 'jobs_in("publish") | all(publishes)'
finish

setup
run "release workflow: the jobs in publish use no secrets" ok \
  holds 'jobs_in("publish") | all(tostring | test("secrets\\.") | not)'
finish

setup
run "release workflow: publication does not use the environment release" ok \
  holds 'publishing_jobs | all(environment != "release")'
finish

setup
run "release workflow: the release job keeps the environment release" ok \
  holds '.jobs.release.with.environment == "release"'
finish

setup
run "release workflow: the tests of the image only read" ok \
  holds '.jobs["build-test"] | .permissions == {"contents": "read"} and environment == null'
finish

summary
