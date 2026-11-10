# shellcheck shell=bash
# Tests of .github/scripts/annotate-release.sh with a stub of gh.
# shellcheck disable=SC2154 # work comes from setup

annotate_reference="ghcr.io/flakeyard/image-devcontainer:v1.2.3@sha256:abc"

# annotate_setup: notes of the release v1.2.3 that do not name the image.
annotate_setup() {
  stubbed_setup
  apply GH_TOKEN=t REPOSITORY=flakeyard/image-devcontainer TAG=v1.2.3
  apply REFERENCE="$annotate_reference" NOTES="$work/notes"
  printf '## 1.2.3\n\n### Features\n\n* something\n' >"$work/notes"
}

# image_lines: the number of lines of the notes that name the image.
image_lines() { grep -c '^Image:' "$work/notes"; }

annotate_setup
run "annotate-release: adds the image to the notes" ok .github/scripts/annotate-release.sh
expect_line "$work/notes" "Image: \`$annotate_reference\`"
expect_line "$work/notes" "* something"
finish

annotate_setup
run "annotate-release: adds it once" ok .github/scripts/annotate-release.sh
: >"$work/calls"
run "annotate-release: a rerun changes nothing" ok .github/scripts/annotate-release.sh
expect no-calls
if [[ -n $current && $(image_lines) != 1 ]]; then report "notes: $(cat "$work/notes")"; fi
finish

annotate_setup
printf '## 1.2.3\r\n\r\n* something\r\n\r\n%s\r\n' "Image: \`$annotate_reference\`" >"$work/notes"
run "annotate-release: notes with CRLF line endings that name the image" ok .github/scripts/annotate-release.sh
expect no-calls
expect message "already name"
finish
