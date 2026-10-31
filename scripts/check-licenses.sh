#!/usr/bin/env bash
# Usage: check-licenses OUTPUT [FLAKE]
#
# Generates the SBOM of the image of this system with sbomnix into OUTPUT (a
# CycloneDX JSON file), completes it and checks it (FY-0027):
#   - every store path of the image is an output of a component;
#   - every output of a component is a store path of the image;
#   - every component has licenses, each an object with an SPDX id or a name;
#   - no license forbids redistribution.
# Inputs (environment): CLOSURE, the store paths of the image, one per line;
# CLOSURE_ROOT, the store path the SBOM is generated from, which is not in
# the image;
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

# The SBOM describes the closure of CLOSURE_ROOT: CLOSURE and CLOSURE_ROOT
# itself, a text file that only names the contents of the image. sbomnix puts
# it in .metadata.component; it is excluded in case a component has it too.
# Components without nix:output_path name no store path and are only checked
# for licenses.
report=$(jq -r --rawfile closure "$CLOSURE" --rawfile deny "$NON_REDISTRIBUTABLE" \
  --arg root "$CLOSURE_ROOT" '
  def nonempty_string: strings | select(. != "");
  ($closure | split("\n") | map(select(. != ""))) as $paths
  | ($deny | split("\n") | map(select(. != ""))) as $denied
  | [.components[]?.properties[]? | select(.name == "nix:output_path") | .value] as $outputs
  | ($paths - $outputs | map("missing \(.)")) +
    ($outputs - $paths - [$root] | unique | map("extra \(.)")) +
    [.components[]? | .name as $n
      | if (.licenses // []) | length == 0 then "unlicensed \($n)"
        elif .licenses | type != "array" then "malformed \(.licenses | tojson) \($n)"
        else .licenses[]
          # A license is an object with a non-empty string id or name.
          | ([.license? | objects | (.id | nonempty_string) // (.name | nonempty_string)] | first) as $l
          | if $l == null then "malformed \(tojson) \($n)"
            elif $denied | index($l) then "forbidden \($l) \($n)"
            else empty end
        end]
  | .[]' "$output")

count=$(jq '.components | length' "$output")
echo "The SBOM of $system has $count components for $(grep -c . "$CLOSURE") store paths."
if [[ -n $report ]]; then
  echo "error: the SBOM does not pass:" >&2
  printf '  %s\n' "$report" >&2
  exit 1
fi
