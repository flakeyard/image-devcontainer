# Definitions of an SBOM component that complete.jq and problems.jq share.

# has_licenses: whether a component lists any license.
def has_licenses: (.licenses // []) | length > 0;
