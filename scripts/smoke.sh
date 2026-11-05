#!/usr/bin/env bash
# Usage: smoke TESTS_DIR
#
# Loads the image of this system into docker and runs the smoke tests of
# TESTS_DIR (ADR-0001). Needs docker and passwordless sudo, as on GitHub-hosted
# runners.
set -euo pipefail

tests=$(cd -- "$1" && pwd)

stream=$(nix build --no-link --no-update-lock-file --print-out-paths .#image)
loaded=$("$stream" | docker load)
IMAGE=${loaded##*: }
echo "Testing $IMAGE"
export IMAGE

WORK=$(mktemp -d)
trap 'sudo rm -rf -- "$WORK"' EXIT

# shellcheck disable=SC1091 # the tests come from the argument
source "$tests/lib.sh"
suite "$tests"/{core,nix,editor,hardening}.sh
