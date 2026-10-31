#!/usr/bin/env bash
# Usage: smoke TESTS_DIR [FLAKE]
#
# Loads the image of this system into docker and runs the smoke tests of
# TESTS_DIR (FY-0005). Needs docker and passwordless sudo, as on GitHub-hosted
# runners.
set -euo pipefail

tests=$(cd -- "$1" && pwd)
flake=${2:-.}

stream=$(nix build --no-link --no-update-lock-file --print-out-paths "$flake#image")
loaded=$("$stream" | docker load)
IMAGE=${loaded##*: }
echo "Testing $IMAGE"
export IMAGE

WORK=$(mktemp -d)
trap 'sudo rm -rf -- "$WORK"' EXIT

# shellcheck disable=SC1091 # the tests come from the argument
source "$tests/lib.sh"
suite "$tests"/{core,nix,editor,hardening}.sh
