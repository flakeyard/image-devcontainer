# shellcheck shell=bash
# Tests of scripts/check/licenses.sh with stubs of nix and sbomnix.
# shellcheck disable=SC2154 # work comes from setup

a=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-curl-8.0
b=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-nix-cmd-2.35.3
c=/nix/store/cccccccccccccccccccccccccccccccc-zlib-1.3
closure_root=/nix/store/rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr-image-closure-root

# licenses_setup: the closure $a and $b, licenses that forbid redistribution
# and a known license of nix-cmd.
licenses_setup() {
  stubbed_setup
  apply SYSTEM=x86_64-linux SBOM="$work/sbom.json" CLOSURE="$work/closure" CLOSURE_ROOT="$closure_root"
  apply NON_REDISTRIBUTABLE="$work/deny" KNOWN_LICENSES="$work/known.json"
  apply LICENSES_JQ="$code_root/scripts/check/licenses" IMAGE_LIB="$code_root/scripts/lib/image.sh"
  printf '%s\n%s\n' "$a" "$b" >"$work/closure"
  printf 'BUSL-1.1\nunfree\n' >"$work/deny"
  echo '{"nix-cmd": ["LGPL-2.1-or-later"]}' >"$work/known.json"
}

# component NAME PATH LICENSES_JSON
component() {
  jq -cn --arg n "$1" --arg p "$2" --argjson l "$3" \
    '{name: $n, properties: [{name: "nix:output_path", value: $p}]} + (if $l == null then {} else {licenses: $l} end)'
}

# sbom COMPONENT...
sbom() { jq -cs '{components: .}' <<<"$(printf '%s\n' "$@")" >"$work/sbom.json"; }

# check_licenses NAME EXPECTED: test NAME runs the check, with the completed
# SBOM in $work/out.json; EXPECTED is ok or fail.
check_licenses() {
  local name=$1 expected=$2
  run "licenses: $name" "$expected" scripts/check/licenses.sh -- "$work/out.json"
}

curl='[{"license":{"id":"curl"}}]'

licenses_setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)"
check_licenses "complete and licensed, with a known license" ok
if [[ -n $current ]] && ! jq -e '.components[1].licenses[0].license.id == "LGPL-2.1-or-later"' "$work/out.json" >/dev/null; then
  report "nix-cmd was not completed: $(cat "$work/out.json")"
fi
expect message "2 components for 2 store paths"
finish

licenses_setup
sbom "$(component curl "$a" "$curl")"
check_licenses "a store path without a component" fail
expect message "missing $b"
finish

licenses_setup
echo '{"components": []}' >"$work/sbom.json"
check_licenses "an empty SBOM" fail
expect message "missing $a"
finish

licenses_setup
sbom "$(component curl "$a" '[{"expression":"BUSL-1.1"}]')" "$(component nix-cmd "$b" null)"
check_licenses "a license expression" fail
expect message "malformed"
finish

licenses_setup
sbom "$(component curl "$a" '[{"license":{"url":"u"}}]')" "$(component nix-cmd "$b" null)"
check_licenses "a license without id or name" fail
expect message "malformed"
finish

licenses_setup
sbom "$(component curl "$a" '[{"license":{"id":"MIT"}},{"license":{"id":"BUSL-1.1"}}]')" "$(component nix-cmd "$b" null)"
check_licenses "one forbidden license among others" fail
expect message "forbidden BUSL-1.1 curl"
finish

licenses_setup
sbom "$(component curl "$a" '[{"license":{"name":"unfree"}}]')" "$(component nix-cmd "$b" null)"
check_licenses "a forbidden license by name" fail
expect message "forbidden unfree curl"
finish

licenses_setup
sbom "$(component curl "$a" null)" "$(component nix-cmd "$b" null)"
check_licenses "a component without a license" fail
expect message "unlicensed curl"
finish

# Licenses that are not an object with a string id or name.
for license in '"MIT"' 1 '["MIT"]' '{"id":1}' '{"id":""}' '{"name":["MIT"]}'; do
  licenses_setup
  sbom "$(component curl "$a" "[{\"license\":$license}]")" "$(component nix-cmd "$b" null)"
  check_licenses "a malformed license $license" fail
  expect message "malformed"
  finish
done

for licenses in '"MIT"' '["MIT"]' '{"license":{"id":"MIT"}}'; do
  licenses_setup
  sbom "$(component curl "$a" "$licenses")" "$(component nix-cmd "$b" null)"
  check_licenses "malformed licenses $licenses" fail
  expect message "malformed"
  finish
done

licenses_setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)" "$(component zlib "$c" '[{"license":{"id":"Zlib"}}]')"
check_licenses "a component output outside the image" fail
expect message "extra $c"
finish

licenses_setup
dev=/nix/store/dddddddddddddddddddddddddddddddd-curl-8.0-dev
sbom "$(component curl "$a $dev" "$curl")" "$(component nix-cmd "$b" null)"
check_licenses "outputs of an image component that the image does not contain" ok
finish

licenses_setup
sbom "$(jq -cn --arg a "$a" --arg dev "$dev" --argjson l "$curl" \
  '{name: "curl", licenses: $l, properties: [{name: "nix:output_path", value: $dev}, {name: "nix:output_path", value: $a}]}')" \
  "$(component nix-cmd "$b" null)"
check_licenses "one output path property per output" ok
finish

licenses_setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)" "$(component image-closure-root "$closure_root" "$curl")"
check_licenses "the closure root is not extra" ok
finish

licenses_setup
sbom "$(component curl "$a" "$curl")" "$(component nix-cmd "$b" null)" '{"name":"source","licenses":[{"license":{"id":"MIT"}}]}'
check_licenses "a component without an output path" ok
finish
