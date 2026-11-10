#!/usr/bin/env bash
# Usage: publish-digest ARCHIVE [FLAKE]
#
# Streams the image of this system into ARCHIVE and prints its digest as crane
# pushes it (FY-0032: the tool that computes a platform digest also pushes it).
# Inputs (environment): IMAGE_LIB, scripts/lib/image.sh.
set -euo pipefail
# Command substitutions fail like other commands.
shopt -s inherit_errexit

archive=$1
flake=${2:-.}
# shellcheck source=/dev/null # scripts/lib/image.sh, from the app
source "$IMAGE_LIB"
stream=$(image_stream "$flake")
"$stream" >"$archive"
crane digest --tarball "$archive"
