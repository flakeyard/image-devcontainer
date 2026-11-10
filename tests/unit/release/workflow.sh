# shellcheck shell=bash
# Static tests of .github/workflows/release.yaml: the environments of its jobs
# (FY-0032, FY-0030). A job publishes when it may write to the package or
# attest.
# shellcheck disable=SC2016 # jq, not expanded here

readonly RELEASE_DEFINITIONS='
  def environment: .environment | if type == "object" then .name else . end;
  def publishes: (.permissions // {}) | [.packages, .attestations, ."id-token"] | any(. == "write");
  def publishing_jobs: [.jobs[] | select(publishes)];
  def jobs_in($name): [.jobs[] | select(environment == $name)];
  def may_be_skipped: has("if") or has("needs");
  def names_matrix: (.name // "") | test("matrix\\.");
'

if require_yq .github/workflows/release.yaml; then
  release_workflow=$(load_yaml .github/workflows/release.yaml)

  # A job skipped before its matrix expands shows its name unexpanded; GitHub
  # appends the matrix values to a name without them.
  yaml_check "$release_workflow" "release workflow: matrix jobs that may be skipped name no matrix value" \
    "$RELEASE_DEFINITIONS"'[.jobs[] | select(has("strategy") and may_be_skipped and names_matrix)] == []'
  yaml_check "$release_workflow" "release workflow: every job that publishes runs in publish" \
    "$RELEASE_DEFINITIONS"'publishing_jobs | length > 0 and all(environment == "publish")'
  yaml_check "$release_workflow" "release workflow: only jobs that publish run in publish" \
    "$RELEASE_DEFINITIONS"'jobs_in("publish") | all(publishes)'
  yaml_check "$release_workflow" "release workflow: the jobs in publish use no secrets" \
    "$RELEASE_DEFINITIONS"'jobs_in("publish") | all(tostring | test("secrets\\.") | not)'
  yaml_check "$release_workflow" "release workflow: publication does not use the environment release" \
    "$RELEASE_DEFINITIONS"'publishing_jobs | all(environment != "release")'
  yaml_check "$release_workflow" "release workflow: the release job keeps the environment release" \
    "$RELEASE_DEFINITIONS"'.jobs.release.with.environment == "release"'
  yaml_check "$release_workflow" "release workflow: the tests of the image only read" \
    "$RELEASE_DEFINITIONS"'.jobs["build-test"] | .permissions == {"contents": "read"} and environment == null'
fi
