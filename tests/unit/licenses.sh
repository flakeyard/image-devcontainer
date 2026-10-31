#!/usr/bin/env bash
# Unit tests of scripts/check-licenses.sh with stubs of nix and sbomnix.
# Inputs (environment): SCRIPTS, STUBS.
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

a=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-curl-8.0
b=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-nix-cmd-2.35.3
c=/nix/store/cccccccccccccccccccccccccccccccc-zlib-1.3
root=/nix/store/rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr-image-closure-root

setup() {
  work=$(mktemp -d)
  export PATH=$STUBS:$PATH SYSTEM=x86_64-linux CALLS=$work/calls
  export SBOM=$work/sbom.json CLOSURE=$work/closure CLOSURE_ROOT=$root
  export NON_REDISTRIBUTABLE=$work/deny KNOWN_LICENSES=$work/known.json
  export COMPLETE_LICENSES_JQ=$SCRIPTS/complete-licenses.jq SBOM_PROBLEMS_JQ=$SCRIPTS/sbom-problems.jq
  printf '%s\n%s\n' "$a" "$b" >"$CLOSURE"
  printf 'BUSL-1.1\nunfree\n' >"$NON_REDISTRIBUTABLE"
  echo '{"nix-cmd": ["LGPL-2.1-or-later"]}' >"$KNOWN_LICENSES"
}

# component NAME PATH LICENSES_JSON
component() {
  jq -cn --arg n "$1" --arg p "$2" --argjson l "$3" \
    '{name: $n, properties: [{name: "nix:output_path", value: $p}]} + (if $l == null then {} else {licenses: $l} end)'
}

# sbom COMPONENT...
sbom() { jq -cs '{components: .}' <<<"$(printf '%s\n' "$@")" >"$SBOM"; }

# check_licenses: the check, with the completed SBOM in $work/out.json.
check_licenses() { "$SCRIPTS/check-licenses.sh" "$work/out.json"; }

curl='[{"license":{"id":"curl"}}]'

setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)"
run "complete and licensed, with a known license" ok check_licenses
if still_passing && ! jq -e '.components[1].licenses[0].license.id == "LGPL-2.1-or-later"' "$work/out.json" >/dev/null; then
  report "nix-cmd was not completed: $(cat "$work/out.json")"
fi
expect message "2 components for 2 store paths"
finish

setup
sbom "$(component curl "$a" "$curl")"
run "a store path without a component" fail check_licenses
expect message "missing $b"
finish

setup
echo '{"components": []}' >"$SBOM"
run "an empty SBOM" fail check_licenses
expect message "missing $a"
finish

setup
sbom "$(component curl "$a" '[{"expression":"BUSL-1.1"}]')" "$(component nix-cmd "$b" null)"
run "a license expression" fail check_licenses
expect message "malformed"
finish

setup
sbom "$(component curl "$a" '[{"license":{"url":"u"}}]')" "$(component nix-cmd "$b" null)"
run "a license without id or name" fail check_licenses
expect message "malformed"
finish

setup
sbom "$(component curl "$a" '[{"license":{"id":"MIT"}},{"license":{"id":"BUSL-1.1"}}]')" "$(component nix-cmd "$b" null)"
run "one forbidden license among others" fail check_licenses
expect message "forbidden BUSL-1.1 curl"
finish

setup
sbom "$(component curl "$a" '[{"license":{"name":"unfree"}}]')" "$(component nix-cmd "$b" null)"
run "a forbidden license by name" fail check_licenses
expect message "forbidden unfree curl"
finish

setup
sbom "$(component curl "$a" null)" "$(component nix-cmd "$b" null)"
run "a component without a license" fail check_licenses
expect message "unlicensed curl"
finish

# Licenses that are not an object with a string id or name.
for license in '"MIT"' 1 '["MIT"]' '{"id":1}' '{"id":""}' '{"name":["MIT"]}'; do
  setup
  sbom "$(component curl "$a" "[{\"license\":$license}]")" "$(component nix-cmd "$b" null)"
  run "a malformed license $license" fail check_licenses
  expect message "malformed"
  finish
done

for licenses in '"MIT"' '["MIT"]' '{"license":{"id":"MIT"}}'; do
  setup
  sbom "$(component curl "$a" "$licenses")" "$(component nix-cmd "$b" null)"
  run "malformed licenses $licenses" fail check_licenses
  expect message "malformed"
  finish
done

setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)" "$(component zlib "$c" '[{"license":{"id":"Zlib"}}]')"
run "a component output outside the image" fail check_licenses
expect message "extra $c"
finish

setup
dev=/nix/store/dddddddddddddddddddddddddddddddd-curl-8.0-dev
sbom "$(component curl "$a $dev" "$curl")" "$(component nix-cmd "$b" null)"
run "outputs of an image component that the image does not contain" ok check_licenses
finish

setup
sbom "$(jq -cn --arg a "$a" --arg dev "$dev" --argjson l "$curl" \
  '{name: "curl", licenses: $l, properties: [{name: "nix:output_path", value: $dev}, {name: "nix:output_path", value: $a}]}')" \
  "$(component nix-cmd "$b" null)"
run "one output path property per output" ok check_licenses
finish

setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)" "$(component image-closure-root "$root" "$curl")"
run "the closure root is not extra" ok check_licenses
finish

setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)" '{"name":"source","licenses":[{"license":{"id":"MIT"}}]}'
run "a component without an output path" ok check_licenses
finish

summary
