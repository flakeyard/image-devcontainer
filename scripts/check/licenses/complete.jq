# Completes the components of a CycloneDX SBOM that have no license with the
# licenses of $known[0], an object of component names and SPDX identifiers for
# components sbomnix cannot match. Used by check/licenses.sh.

# has_licenses: whether a component lists any license.
def has_licenses: (.licenses // []) | length > 0;

# base_name: the name of a component without a trailing version.
def base_name: .name | sub("-[0-9][0-9.]*$"; "");

# known_licenses: the license entries $known has for a component, or null.
def known_licenses: $known[0][base_name] | if . then map({license: {id: .}}) end;

# complete: a component with licenses, or with the known ones when it has none.
def complete: if has_licenses or (known_licenses | not) then . else .licenses = known_licenses end;

.components |= map(complete)
