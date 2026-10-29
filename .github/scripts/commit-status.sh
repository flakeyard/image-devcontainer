#!/usr/bin/env bash
# Posts a commit status for a run started by workflow_dispatch, whose check
# runs do not count for required checks (FY-0020).
# Inputs (environment): GH_TOKEN, REPO, SHA, STATE, CONTEXT, RUN_URL.
set -euo pipefail
gh api --silent -X POST "repos/$REPO/statuses/$SHA" \
  -f state="$STATE" -f context="$CONTEXT" -f target_url="$RUN_URL" \
  -f description="GitHub Actions run"
