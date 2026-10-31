#!/usr/bin/env bash
# Usage: platform-digest ARCHIVE [FLAKE]
#
# Streams the image of this system into ARCHIVE and prints its digest as crane
# pushes it (FY-0027: the tool that computes a platform digest also pushes it).
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

archive=$1
flake=${2:-.}
stream=$(nix build --no-link --no-update-lock-file --print-out-paths "$flake#image")
"$stream" >"$archive"
crane digest --tarball "$archive"
