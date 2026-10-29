#!/usr/bin/env bash
# Usage: check-licenses OUTPUT [FLAKE]
#
# Generates the SBOM of the image of this system with sbomnix into OUTPUT (a
# CycloneDX JSON file) and checks it (FY-0027): every component has a
# license, and none of them forbids redistribution. Inputs (environment):
# NON_REDISTRIBUTABLE, a file with the identifiers of such licenses, one per
# line, generated from the license list of nixpkgs.
set -euo pipefail

output=$1
flake=${2:-.}
system=$(nix eval --raw --impure --expr builtins.currentSystem)

sbomnix "$flake#packages.$system.image.closureRoot" --cdx "$output" >&2

components=$(jq '.components | length' "$output")
unlicensed=$(jq -r '.components[] | select((.licenses // []) | length == 0) | .name' "$output" | sort -u)
forbidden=$(jq -r '.components[] | .name as $n | .licenses[]?.license | (.id // .name) | "\(.) \($n)"' "$output" |
  awk 'NR == FNR { bad[$0] = 1; next } bad[$1] { print }' "$NON_REDISTRIBUTABLE" - | sort -u)

echo "The SBOM of $system has $components components."
status=0
if [[ -n $unlicensed ]]; then
  echo "error: components without a license: $(paste -sd' ' <<<"$unlicensed")" >&2
  status=1
fi
if [[ -n $forbidden ]]; then
  echo "error: licenses that forbid redistribution (license component):" >&2
  printf '  %s\n' "$forbidden" >&2
  status=1
fi
exit "$status"
