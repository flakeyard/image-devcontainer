#!/usr/bin/env bash
# Usage: check-licenses OUTPUT [FLAKE]
#
# Generates the SBOM of the image of this system with sbomnix into OUTPUT (a
# CycloneDX JSON file), completes it and checks it (FY-0027):
#   - every store path of the image is an output of a component;
#   - every component has licenses, each with an SPDX id or a name;
#   - no license forbids redistribution.
# Inputs (environment): CLOSURE, the store paths of the image, one per line;
# NON_REDISTRIBUTABLE, identifiers of licenses that forbid redistribution,
# one per line, from nixpkgs; KNOWN_LICENSES, a JSON object of component names
# and SPDX identifiers for components sbomnix cannot match.
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

report=$(jq -r --rawfile closure "$CLOSURE" --rawfile deny "$NON_REDISTRIBUTABLE" '
  ($closure | split("\n") | map(select(. != ""))) as $paths
  | ($deny | split("\n") | map(select(. != ""))) as $denied
  | [.components[]?.properties[]? | select(.name == "nix:output_path") | .value] as $outputs
  | ($paths - $outputs | map("missing \(.)")) +
    [.components[]? | .name as $n
      | if (.licenses // []) | length == 0 then "unlicensed \($n)"
        else .licenses[]
          | if .license.id? // .license.name? then
              (.license.id // .license.name) as $l
              | if ($denied | index($l)) then "forbidden \($l) \($n)" else empty end
            else "malformed \(tojson) \($n)" end
        end]
  | .[]' "$output")

count=$(jq '.components | length' "$output")
echo "The SBOM of $system has $count components for $(grep -c . "$CLOSURE") store paths."
if [[ -n $report ]]; then
  echo "error: the SBOM does not pass:" >&2
  printf '  %s\n' "$report" >&2
  exit 1
fi
