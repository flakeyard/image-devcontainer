#!/usr/bin/env bash
# Unit tests of the scripts of the apps and of .github, and static tests of
# the workflows, with the harness and the stubs of gh, date and sleep of the
# shell library in SHELL_LIB and the other stubs in tests/bin. tests/unit
# mirrors scripts/: one suite per script, and those of .github in release/
# and workflows/. The static tests need mikefarah yq.
# Usage: SHELL_LIB=<shell library> tests/run.sh
# shellcheck source-path=SCRIPTDIR
set -uo pipefail
shopt -s globstar
export LC_ALL=C

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC2034 # read by the checks of the library
code_root=$root
testing=${SHELL_LIB:?the tests need SHELL_LIB, the directory of the shell library}/internal/testing
# shellcheck source=/dev/null
source "$testing/case.sh"
# shellcheck source=/dev/null
source "$testing/checks.sh"
# shellcheck source=/dev/null
source "$testing/fixtures.sh"
# shellcheck source=/dev/null
source "$testing/yaml.sh"
# shellcheck source=/dev/null
source "$testing/consumer/action.sh"
# shellcheck source=lib/checks.sh
source "$root/tests/lib/checks.sh"
# shellcheck source=lib/stubs.sh
source "$root/tests/lib/stubs.sh"

for suite in "$root"/tests/unit/{check,publish,release,workflows}/*.sh; do
  # shellcheck source=/dev/null
  source "$suite"
done

conclude
