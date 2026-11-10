# shellcheck shell=bash
# Tests of .github/actions/attest-once/attested.sh with a stub of gh.
# shellcheck disable=SC2154 # work comes from setup

attested_script=.github/actions/attest-once/attested.sh
provenance=https://slsa.dev/provenance/v1
bom=https://cyclonedx.org/bom

# attested_setup: the digest sha256:abc, without attestations; the API lists
# none with HTTP 404.
attested_setup() {
  stubbed_setup
  apply GH_TOKEN=t REPOSITORY=flakeyard/image-devcontainer IMAGE=ghcr.io/flakeyard/image-devcontainer
  apply DIGEST=sha256:abc PREDICATE=""
}

# listed BODY: the API lists the attestations of the digest with BODY.
listed() {
  local body=$1
  fixture repos/flakeyard/image-devcontainer/attestations/sha256:abc "$body"
}

# attestation TYPE: an attestation of the predicate TYPE as the API lists it;
# "-" is one without an inline bundle.
attestation() {
  local type=$1 payload
  if [[ $type == - ]]; then
    echo '{"bundle": null, "bundle_url": "https://example.invalid/bundle"}'
  else
    payload=$(printf '{"predicateType":"%s"}' "$type" | base64 -w0)
    printf '{"bundle": {"dsseEnvelope": {"payload": "%s"}}}\n' "$payload"
  fi
}

# attestations TYPE...: the API lists attestations of the predicate TYPEs.
attestations() {
  local type
  listed "$(for type; do attestation "$type"; done | jq -s '{attestations: .}')"
}

attested_setup
apply ATTESTED=1
run "attested: true when an attestation verifies" ok "$attested_script"
expect output attested true
expect call "--signer-workflow flakeyard/image-devcontainer/.github/workflows/release.yaml"
expect no-call "--source-digest"
expect call "--deny-self-hosted-runners"
finish

attested_setup
apply ATTESTED=1
attestations "$provenance" "$bom"
run "attested: an unchanged image reuses the previous release's attestation" ok "$attested_script"
expect output attested true
finish

attested_setup
run "attested: false when the digest has no attestation" ok "$attested_script"
expect output attested false
# The body of the 404 is not read as a list of attestations.
expect no-message "error"
finish

attested_setup
attestations "$bom"
transient_failures repos/flakeyard/image-devcontainer/attestations/sha256:abc 1
run "attested: a transient API error is retried" ok "$attested_script"
expect output attested false
expect sleeps "5"
finish

attested_setup
apply PREDICATE="$bom"
attestations "$provenance"
run "attested: an SBOM is missing although provenance exists" ok "$attested_script"
expect output attested false
expect call "--predicate-type $bom"
finish

attested_setup
attestations "$provenance" "$bom"
run "attested: an attestation that does not verify fails" fail "$attested_script"
expect message "none verifies"
expect output attested ""
finish

attested_setup
listed "HTTP 500"
run "attested: an API error fails, whatever the verification reported" fail "$attested_script"
expect message "cannot list the attestations"
expect message "HTTP 500"
expect output attested ""
finish

attested_setup
attestations - "$provenance"
run "attested: an attestation without an inline bundle fails" fail "$attested_script"
expect message "no inline bundle"
expect output attested ""
finish

attested_setup
attestations "$bom"
run "attested: an attestation of another type does not count" ok "$attested_script"
expect output attested false
finish
