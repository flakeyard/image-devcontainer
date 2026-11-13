#!/usr/bin/env bash
# Usage: check-reproducible
#
# Checks that the image is reproducible (FY-0032): rebuilds with --rebuild
# every derivation of the image that cache.nixos.org does not have, then
# streams the image twice and compares the archives. The derivations come
# from the cache, not from the local store, so that a store that has built
# the image already checks them all the same.
# Inputs (environment): IMAGE_LIB, scripts/lib/image.sh.
set -euo pipefail
shopt -s inherit_errexit

# shellcheck source=/dev/null # scripts/lib/image.sh, from the app
source "$IMAGE_LIB"
installable=.#image
# The binary cache of the image (ADR-0001): what it lacks is built here.
cache=https://cache.nixos.org
store_dir=/nix/store

# lines ARRAY TEXT: sets ARRAY to the lines of TEXT; none when TEXT is empty.
# Commands run in $(...) rather than <(...), so that their failure ends the
# check.
lines() { mapfile -t "$1" < <(printf '%s' "$2"); }

# uncached_derivations DERIVATION: prints DERIVATION and the derivations it
# needs, whose outputs the cache lacks, as Nix would build them with no other
# store. The inputs of a derivation that the cache has are not needed.
uncached_derivations() {
  local frontier=("$1") visited=() shown missing next
  while ((${#frontier[@]} > 0)); do
    shown=$(nix derivation show "${frontier[@]}")
    missing=$(missing_derivations "$shown")
    [[ -n $missing ]] || return 0
    printf '%s\n' "$missing"
    visited+=("${frontier[@]}")
    next=$(input_derivations "$shown" "$missing" | unvisited "${visited[@]}")
    lines frontier "$next"
  done
}

# missing_derivations SHOWN: of the derivations in SHOWN, the output of `nix
# derivation show`, prints those with an output that the cache lacks.
# Fixed-output derivations, such as sources, have no path there; their hash
# fixes their output, so they need no rebuild.
missing_derivations() {
  local shown=$1 pairs outputs lacking
  # "DERIVATION OUTPUT" for each output with a path, as store paths.
  pairs=$(jq -r --arg dir "$store_dir" '.derivations | to_entries[]
    | "\($dir)/\(.key) \($dir)/\(.value.outputs[].path // empty)"' <<<"$shown")
  lines outputs "$(cut -d' ' -f2 <<<"$pairs")"
  lacking=$(uncached "${outputs[@]}")
  awk 'FILENAME == ARGV[1] { lacking[$1]; next } $2 in lacking && !seen[$1]++ { print $1 }' \
    <(printf '%s\n' "$lacking") - <<<"$pairs"
}

# uncached PATH...: prints the PATHs that the cache does not have.
uncached() { nix-store --store "$cache" --check-validity --print-invalid "$@"; }

# input_derivations SHOWN DERIVATIONS: prints the input derivations of the
# DERIVATIONS, one per line, in SHOWN, the output of `nix derivation show`.
input_derivations() {
  local shown=$1 derivations
  lines derivations "$2"
  jq -r --arg dir "$store_dir" '.derivations | to_entries[] | select(.key | IN($ARGS.positional[]))
    | .value.inputs.drvs | keys[] | "\($dir)/\(.)"' --args "${derivations[@]#"$store_dir"/}" <<<"$shown" \
    | sort -u
}

# unvisited VISITED...: prints the lines of stdin that are not a VISITED.
unvisited() {
  awk 'FILENAME == ARGV[1] { visited[$0]; next } !($0 in visited)' <(printf '%s\n' "$@") -
}

image=$(nix path-info --derivation --no-update-lock-file "$installable")
needed=$(uncached_derivations "$image")
lines derivations "$needed"
echo "The image needs ${#derivations[@]} derivations that $cache does not have."
# The customisation layer of the image is never in the cache: none means that
# this check checks nothing.
if ((${#derivations[@]} == 0)); then
  echo "error: found no derivation of the image to rebuild" >&2
  exit 1
fi

printf 'Rebuilding %s\n' "${derivations[@]}"
# Builds what the local store lacks, then rebuilds all of them in one build;
# --keep-going reports every derivation that fails or differs, not only the
# first.
nix build --no-link "${derivations[@]/%/^*}"
nix build --no-link --rebuild --keep-going "${derivations[@]/%/^*}"

stream=$(image_stream)
first=$("$stream" | sha256sum)
second=$("$stream" | sha256sum)
if [[ $first != "$second" ]]; then
  echo "error: two streams of the image differ: ${first%% *} and ${second%% *}" >&2
  exit 1
fi
echo "Two streams of the image are equal: ${first%% *}"
