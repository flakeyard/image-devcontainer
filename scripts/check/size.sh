#!/usr/bin/env bash
# Usage: check-size BUDGET_FILE
#
# Fails when the image of this system is larger than its budget (ADR-0001).
# BUDGET_FILE has lines "<system> <MiB>". Raise a budget only on purpose, in
# a pull request that says why the image grew.
# Inputs (environment): IMAGE_LIB, scripts/lib/image.sh.
set -euo pipefail

budget_file=$1
# shellcheck source=/dev/null # scripts/lib/image.sh, from the app
source "$IMAGE_LIB"
system=$(current_system)
budget=$(awk -v s="$system" '$1 == s { print $2 }' "$budget_file")
if [[ ! $budget =~ ^[0-9]+$ ]]; then
  echo "error: no budget for $system in $budget_file" >&2
  exit 1
fi

stream=$(image_stream)
bytes=$("$stream" | wc -c)
mib=$(((bytes + 1048575) / 1048576))
echo "The image of $system is $mib MiB ($bytes bytes); its budget is $budget MiB."
if ((mib > budget)); then
  echo "error: the image exceeds its budget; raise it in $budget_file only on purpose" >&2
  exit 1
fi
