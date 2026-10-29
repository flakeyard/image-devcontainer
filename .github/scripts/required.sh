#!/usr/bin/env bash
# Fails unless every job this job depends on succeeded. Only the job "pending",
# which runs for workflow_dispatch alone, may be skipped.
# Inputs (environment): NEEDS, the needs context as JSON.
set -euo pipefail
failed=$(jq -r 'to_entries[]
  | select(.value.result != "success" and (.key != "pending" or .value.result != "skipped"))
  | "\(.key): \(.value.result)"' <<<"$NEEDS")
if [[ -n $failed ]]; then
  echo "::error::Jobs that did not succeed: $(paste -sd',' <<<"$failed")"
  exit 1
fi
