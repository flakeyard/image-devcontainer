#!/usr/bin/env bash
# Usage: check-reproducible [FLAKE]
#
# Checks that the image is reproducible (FY-0027): rebuilds with --rebuild
# every derivation of the image that is not in a binary cache, then streams
# the image twice and compares the archives. Run it before anything else
# builds the image, so that Nix still knows which derivations it builds.
set -euo pipefail

flake=${1:-.}
installable=$flake#image

# own_derivations: reads the output of `nix build --dry-run` and prints the
# derivations it will build.
own_derivations() {
  awk '/will be built:$/ { built = 1; next }
       /^[^ ]/ { built = 0 }
       built && $1 ~ /^\/nix\/store\/.*\.drv$/ { print $1 }'
}

plan=$(nix build --no-link --dry-run --no-update-lock-file "$installable" 2>&1)
mapfile -t derivations < <(own_derivations <<<"$plan")
echo "The image needs ${#derivations[@]} derivations that are not in a binary cache."

nix build --no-link --no-update-lock-file --print-build-logs "$installable"
if ((${#derivations[@]} > 0)); then
  printf 'Rebuilding %s\n' "${derivations[@]}"
  # One build of all outputs; --keep-going reports every derivation that
  # fails or differs, not only the first.
  nix build --no-link --rebuild --keep-going "${derivations[@]/%/^*}"
fi

stream=$(nix build --no-link --no-update-lock-file --print-out-paths "$installable")
first=$("$stream" | sha256sum)
second=$("$stream" | sha256sum)
if [[ $first != "$second" ]]; then
  echo "error: two streams of the image differ: ${first%% *} and ${second%% *}" >&2
  exit 1
fi
echo "Two streams of the image are equal: ${first%% *}"
