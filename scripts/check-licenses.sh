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
# the image; NON_REDISTRIBUTABLE, identifiers of licenses that forbid
# redistribution, one per line, from nixpkgs; KNOWN_LICENSES, a JSON object of
# component names and SPDX identifiers for components sbomnix cannot match;
# COMPLETE_LICENSES_JQ and SBOM_PROBLEMS_JQ, the jq programs of these steps.
set -euo pipefail
shopt -s inherit_errexit

output=$1
flake=${2:-.}
system=$(nix eval --raw --impure --expr builtins.currentSystem)

# generate_sbom FILE: writes the SBOM of the image as sbomnix makes it.
generate_sbom() {
  local file=$1
  sbomnix "$flake#packages.$system.image.closureRoot" --cdx "$file" >&2
}

# complete_licenses SBOM: prints SBOM, its components without a license
# completed from KNOWN_LICENSES by name without a trailing version.
complete_licenses() {
  local sbom=$1
  jq --slurpfile known "$KNOWN_LICENSES" --from-file "$COMPLETE_LICENSES_JQ" "$sbom"
}

# sbom_problems SBOM: prints the problems of SBOM, one per line.
sbom_problems() {
  local sbom=$1
  jq -r --rawfile closure "$CLOSURE" --rawfile deny "$NON_REDISTRIBUTABLE" \
    --arg root "$CLOSURE_ROOT" --from-file "$SBOM_PROBLEMS_JQ" "$sbom"
}

# print_summary SBOM: prints the number of components and store paths.
print_summary() {
  local sbom=$1 count
  count=$(jq '.components | length' "$sbom")
  echo "The SBOM of $system has $count components for $(grep -c . "$CLOSURE") store paths."
}

# fail_on PROBLEMS: fails listing PROBLEMS, one per line, unless empty.
fail_on() {
  local problems=$1
  [[ -n $problems ]] || return 0
  echo "error: the SBOM does not pass:" >&2
  printf '  %s\n' "$problems" >&2
  exit 1
}

raw=$(mktemp)
trap 'rm -f -- "$raw"' EXIT
generate_sbom "$raw"
complete_licenses "$raw" >"$output"
problems=$(sbom_problems "$output")
print_summary "$output"
fail_on "$problems"
