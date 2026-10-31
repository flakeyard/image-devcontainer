#!/usr/bin/env bash
# Usage: check-licenses OUTPUT [FLAKE]
#
# Generates the SBOM of the image of this system with sbomnix into OUTPUT (a
# CycloneDX JSON file) and checks it (FY-0027): every component has a
# license, and none of them forbids redistribution. Inputs (environment):
# NON_REDISTRIBUTABLE, a file with the identifiers of such licenses, one per
# line, generated from the license list of nixpkgs; KNOWN_LICENSES, a JSON
# object of component names and SPDX identifiers for components sbomnix cannot
# match, with which the SBOM is completed.
set -euo pipefail
shopt -s inherit_errexit

output=$1
flake=${2:-.}
system=$(nix eval --raw --impure --expr builtins.currentSystem)

raw=$(mktemp)
trap 'rm -f -- "$raw"' EXIT
sbomnix "$flake#packages.$system.image.closureRoot" --cdx "$raw" >&2

# Complete components without a license from KNOWN_LICENSES, by name without
# a trailing version.
jq --slurpfile known "$KNOWN_LICENSES" '
  .components |= map(
    if (.licenses // []) | length > 0 then .
    else (.name | sub("-[0-9][0-9.]*$"; "")) as $name
      | if $known[0][$name] then .licenses = [$known[0][$name][] | {license: {id: .}}] else . end
    end)' "$raw" >"$output"

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
