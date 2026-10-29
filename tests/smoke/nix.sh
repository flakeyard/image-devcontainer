# shellcheck shell=bash disable=SC2016,SC2154 # commands run in the container; tests is set by smoke.sh
# Smoke tests of the store, Nix and the image configuration (FY-0005).
# Sourced by scripts/smoke.sh after tests/smoke/lib.sh. Inputs (environment):
# IMAGE; EXPECTED, a directory with nix.conf, env, metadata and nix-version;
# tests, the directory of the smoke tests.

# --- the store and trust ---------------------------------------------------------

test_case "the store and the Nix settings belong to root"
run -- sh -c 'stat -c "%U %a" /nix/store; touch /nix/store/x 2>/dev/null && echo store-written; touch /etc/nix/local.conf 2>/dev/null && echo conf-written; echo checked'
expect_line "root 1775"
expect_line "checked"
expect_no_text "written"

test_case "builds run as build users"
# Build and read the result in the same container.
run -v "$tests/../fixture:/fixture:ro" -- sh -c 'cat "$(nix-build --no-out-link /fixture/uid.nix)"'
grep -qxE '300[0-9][0-9]' <<<"$output" || fail "not built as a build user"

test_case "dev cannot add substituters"
run -- nix store info --option extra-substituters https://untrusted.invalid
expect_text "ignoring untrusted substituter 'https://untrusted.invalid'"

test_case "/etc/nix/local.conf is included"
run -u 0 --entrypoint /bin/sh -- -c 'echo "extra-substituters = https://local.invalid" >/etc/nix/local.conf; nix config show substituters'
expect_text "https://local.invalid"

# --- the configuration ------------------------------------------------------------

test_case "nix.conf is exactly the image's"
run -- cat /etc/nix/nix.conf
[[ $output == "$(<"$EXPECTED/nix.conf")" ]] || fail "nix.conf differs"

test_case "the environment is exactly the image's"
output=$(docker inspect "$IMAGE" --format '{{range .Config.Env}}{{println .}}{{end}}')
[[ $(sed '/^$/d' <<<"$output") == "$(sed '/^$/d' "$EXPECTED/env")" ]] || fail "Env differs"

test_case "the labels and the creation date do not change per commit"
output=$(docker inspect "$IMAGE" --format '{{json .Config.Labels}} {{.Created}}')
[[ $(docker inspect "$IMAGE" --format '{{index .Config.Labels "devcontainer.metadata"}}') == "$(<"$EXPECTED/metadata")" ]] ||
  fail "devcontainer.metadata differs"
expect_no_text "image.version"
expect_no_text "image.revision"
expect_text "1970-01-01T00:00:01Z"

test_case "one Nix version, the same in the client, the daemon and on the runner"
nix_version=$(<"$EXPECTED/nix-version")
run -- sh -c 'nix --version; nix store info | grep Version; for p in /nix/store/*-nix-2.[0-9]*; do basename "$p"; done'
expect_line "nix (Nix) $nix_version"
expect_line "Version: $nix_version"
versions=$(grep -oE -- '-nix-2\.[0-9]+\.[0-9]+$' <<<"$output" | sort -u)
[[ $versions == "-nix-$nix_version" ]] || fail "Nix versions in the store: $(paste -sd' ' <<<"$versions")"
runner=$(nix --version)
[[ ${runner##* } =~ ^${nix_version%.*}\. ]] || fail "the runner has ${runner##* }, the image $nix_version"

# --- garbage collection -----------------------------------------------------------

test_case "garbage collection keeps every store path the image uses"
id=$(start)
poll 20 ready "$id" || fail "the daemon did not answer"
docker exec "$id" nix-collect-garbage >/dev/null 2>&1 || fail "garbage collection failed"
config=$(docker inspect "$IMAGE" --format '{{json .Config}}')
output=$(docker exec "$id" sh -c '
  { grep -rhoE "/nix/store/[a-z0-9]{32}-[^/ \"'"'"':]+" /etc /home/dev /usr/lib 2>/dev/null
    for link in /etc/ssl/certs/* /usr/lib/* /lib*/ld-linux*; do readlink "$link"; done
    cat
  } | grep -oE "/nix/store/[a-z0-9]{32}-[^/ \"'"'"':]+" | sort -u |
  while read -r path; do [ -e "$path" ] || echo "missing $path"; done; echo checked' <<<"$config" 2>&1) || true
expect_line "checked"
expect_no_text "missing"
docker restart "$id" >/dev/null
poll 20 ready "$id" || fail "the daemon did not answer after garbage collection and a restart"
docker rm -f "$id" >/dev/null
