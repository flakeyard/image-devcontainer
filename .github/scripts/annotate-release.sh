#!/usr/bin/env bash
# Adds the image reference to the notes of the release, once (FY-0024,
# FY-0027). Inputs (environment): GH_TOKEN, REPOSITORY, TAG, REFERENCE.
set -euo pipefail
line="Image: \`$REFERENCE\`"
notes=$(gh release view "$TAG" --repo "$REPOSITORY" --json body --jq .body)
if grep -qxF -- "$line" <<<"$notes"; then
  echo "The notes of $TAG already name $REFERENCE."
  exit 0
fi
printf '%s\n\n%s\n' "$notes" "$line" | gh release edit "$TAG" --repo "$REPOSITORY" --notes-file - >/dev/null
echo "Added $REFERENCE to the notes of $TAG."
