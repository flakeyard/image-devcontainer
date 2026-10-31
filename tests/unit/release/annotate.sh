#!/usr/bin/env bash
# Unit tests of .github/scripts/annotate-release.sh with a stub of gh. Inputs
# (environment): SCRIPTS, the .github directory; STUBS, the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls NOTES=$work/notes PATH=$STUBS:$PATH
  export GH_TOKEN=t REPOSITORY=flakeyard/image-devcontainer TAG=v1.2.3
  export REFERENCE="ghcr.io/flakeyard/image-devcontainer:v1.2.3@sha256:abc"
  : >"$CALLS"
  printf '## 1.2.3\n\n### Features\n\n* something\n' >"$NOTES"
}

# image_lines: the number of lines of the notes that name the image.
image_lines() { grep -c '^Image:' "$NOTES"; }

setup
run "annotate-release: adds the image to the notes" ok "$SCRIPTS/scripts/annotate-release.sh"
expect line "$NOTES" "Image: \`$REFERENCE\`"
expect line "$NOTES" "* something"
finish

setup
run "annotate-release: adds it once" ok "$SCRIPTS/scripts/annotate-release.sh"
: >"$CALLS"
run "annotate-release: a rerun changes nothing" ok "$SCRIPTS/scripts/annotate-release.sh"
expect empty "$CALLS"
if still_passing && [[ $(image_lines) != 1 ]]; then report "notes: $(cat "$NOTES")"; fi
finish

summary
