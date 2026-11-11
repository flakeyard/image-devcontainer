#!/usr/bin/env bash
# Usage: check-licenses OUTPUT
#
# Generates the SBOM of the image of this system with sbomnix into OUTPUT (a
# CycloneDX JSON file), completes it and checks it (FY-0032):
#   - every store path of the image is an output of a component;
#   - every output of a component is a store path of the image;
#   - every component has licenses, each an object with an SPDX id or a name;
#   - no license forbids redistribution.
# Inputs (environment): CLOSURE, the store paths of the image, one per line;
# CLOSURE_ROOT, the store path the SBOM is generated from, which is not in
# the image; NIXPKGS, the nixpkgs of the image, whose metadata gives the
# licenses; NON_REDISTRIBUTABLE, identifiers of licenses that forbid
# redistribution, one per line, from nixpkgs; KNOWN_LICENSES, a JSON object of
# component names and SPDX identifiers for components sbomnix cannot match;
# LICENSES_JQ, the directory of the jq programs of these steps; IMAGE_LIB,
# scripts/lib/image.sh.
set -euo pipefail
shopt -s inherit_errexit

output=$1
# shellcheck source=/dev/null # scripts/lib/image.sh, from the app
source "$IMAGE_LIB"
system=$(current_system)

# generate_sbom DIR: writes the SBOM of the image as sbomnix makes it to
# DIR/sbom.cdx.json. sbomnix runs in DIR, where it also writes its other
# outputs and its HTTP cache.
# sbomnix gets the store path and the nixpkgs in NIX_PATH, not the flake: for
# a flake, sbomnix 1.7.6 to 1.10 fetch its nixpkgs input again without
# shallow=1, a clone of the whole nixpkgs history. sbomnix 1.10 documents that
# it skips the nixpkgs metadata for a store path; then no component has a
# license and the check fails with "unlicensed". Revisit on a sbomnix upgrade.
generate_sbom() {
  local dir=$1
  (cd -- "$dir" && NIX_PATH="nixpkgs=$NIXPKGS" sbomnix "$CLOSURE_ROOT" --cdx sbom.cdx.json >&2)
}

# complete_licenses SBOM: prints SBOM, its components without a license
# completed from KNOWN_LICENSES by name without a trailing version.
complete_licenses() {
  local sbom=$1
  jq -L "$LICENSES_JQ" --slurpfile known "$KNOWN_LICENSES" --from-file "$LICENSES_JQ/complete.jq" "$sbom"
}

# sbom_problems SBOM: prints the problems of SBOM, one per line.
sbom_problems() {
  local sbom=$1
  jq -r -L "$LICENSES_JQ" --rawfile closure "$CLOSURE" --rawfile deny "$NON_REDISTRIBUTABLE" \
    --arg root "$CLOSURE_ROOT" --from-file "$LICENSES_JQ/problems.jq" "$sbom"
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

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
generate_sbom "$work"
complete_licenses "$work/sbom.cdx.json" >"$output"
problems=$(sbom_problems "$output")
print_summary "$output"
fail_on "$problems"
