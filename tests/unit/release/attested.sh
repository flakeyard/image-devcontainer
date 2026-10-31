#!/usr/bin/env bash
# Unit tests of .github/actions/attest-once/attested.sh with a stub of gh.
# Inputs (environment): SCRIPTS, the .github directory; STUBS, the stubs.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

setup() {
  work=$(mktemp -d)
  export CALLS=$work/calls GITHUB_OUTPUT=$work/output PATH=$STUBS:$PATH
  export GH_TOKEN=t REPOSITORY=flakeyard/image-devcontainer IMAGE=ghcr.io/flakeyard/image-devcontainer
  export DIGEST=sha256:abc PREDICATE=""
  unset ATTESTED ATTESTATIONS GH_API_ERROR
  : >"$CALLS"
  : >"$GITHUB_OUTPUT"
}

provenance=https://slsa.dev/provenance/v1
bom=https://cyclonedx.org/bom

setup
export ATTESTED=1
run "attested: true when an attestation verifies" ok "$SCRIPTS/actions/attest-once/attested.sh"
expect line "$GITHUB_OUTPUT" attested=true
expect called "--signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml"
expect not_called "--source-digest"
expect called "--deny-self-hosted-runners"
finish

setup
export ATTESTED=1 ATTESTATIONS="$provenance $bom"
run "attested: an unchanged image reuses the previous release's attestation" ok "$SCRIPTS/actions/attest-once/attested.sh"
expect line "$GITHUB_OUTPUT" attested=true
finish

setup
run "attested: false when the digest has no attestation" ok "$SCRIPTS/actions/attest-once/attested.sh"
expect line "$GITHUB_OUTPUT" attested=false
finish

setup
export PREDICATE=$bom ATTESTATIONS=$provenance
run "attested: an SBOM is missing although provenance exists" ok "$SCRIPTS/actions/attest-once/attested.sh"
expect line "$GITHUB_OUTPUT" attested=false
expect called "--predicate-type $bom"
finish

setup
export ATTESTATIONS="$provenance $bom"
run "attested: an attestation that does not verify fails" fail "$SCRIPTS/actions/attest-once/attested.sh"
expect message "none verifies"
expect empty "$GITHUB_OUTPUT"
finish

setup
export GH_API_ERROR=1
run "attested: an API error fails, whatever the verification reported" fail "$SCRIPTS/actions/attest-once/attested.sh"
expect message "cannot list the attestations"
expect empty "$GITHUB_OUTPUT"
finish

setup
export ATTESTATIONS="- $provenance"
run "attested: an attestation without an inline bundle fails" fail "$SCRIPTS/actions/attest-once/attested.sh"
expect message "no inline bundle"
expect empty "$GITHUB_OUTPUT"
finish

setup
export ATTESTATIONS=$bom
run "attested: an attestation of another type does not count" ok "$SCRIPTS/actions/attest-once/attested.sh"
expect line "$GITHUB_OUTPUT" attested=false
finish

summary
