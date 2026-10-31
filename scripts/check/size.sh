#!/usr/bin/env bash
# Usage: check-size BUDGET_FILE [FLAKE]
#
# Fails when the image of this system is larger than its budget (FY-0005).
# BUDGET_FILE has lines "<system> <MiB>". Raise a budget only on purpose, in
# a pull request that says why the image grew.
set -euo pipefail

budget_file=$1
flake=${2:-.}
system=$(nix eval --raw --impure --expr builtins.currentSystem)
budget=$(awk -v s="$system" '$1 == s { print $2 }' "$budget_file")
if [[ ! $budget =~ ^[0-9]+$ ]]; then
  echo "error: no budget for $system in $budget_file" >&2
  exit 1
fi

stream=$(nix build --no-link --no-update-lock-file --print-out-paths "$flake#image")
bytes=$("$stream" | wc -c)
mib=$(((bytes + 1048575) / 1048576))
echo "The image of $system is $mib MiB ($bytes bytes); its budget is $budget MiB."
if ((mib > budget)); then
  echo "error: the image exceeds its budget; raise it in $budget_file only on purpose" >&2
  exit 1
fi
