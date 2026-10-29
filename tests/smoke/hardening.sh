# shellcheck shell=bash disable=SC2016,SC2034,SC2154 # container commands; shared variables
# Smoke tests of the boundary between dev and root (FY-0005), from the code
# audit. Sourced by scripts/smoke.sh after tests/smoke/lib.sh. Inputs
# (environment): IMAGE, WORK, tests.

test_case "root never runs programs from dev's profile"
id=$(start)
poll 20 ready "$id" || fail "the daemon did not answer"
docker exec -u dev "$id" sh -c '
  rm -rf "$HOME/.nix-profile" && mkdir -p "$HOME/.nix-profile/bin" &&
  for tool in sh bash direnv nix id; do
    printf "#!/bin/sh\ntouch /tmp/ran-from-profile\nexit 0\n" >"$HOME/.nix-profile/bin/$tool"
    chmod +x "$HOME/.nix-profile/bin/$tool"
  done'
output=$(docker exec "$id" sh -c 'id -u') || true
expect_line "0"
docker exec "$id" bash -ic true >/dev/null 2>&1 || true
docker exec "$id" bash -lc true >/dev/null 2>&1 || true
output=$(docker exec "$id" sh -c 'ls /tmp/ran-from-profile 2>&1 || echo clean') || true
expect_line "clean"
output=$(docker exec -u dev "$id" bash -ic 'command -v direnv') || true
expect_text "/home/dev/.nix-profile/bin/direnv"
docker rm -f "$id" >/dev/null

test_case "NIX_CONFIG of the container does not reach the daemon"
run -e NIX_CONFIG='trusted-users = root dev' -- nix store info
expect_line "Trusted: 0"

test_case "rejects a DEV_UID that does not fit a uid, also after a restart"
id=$(start -e DEV_UID=4294967296)
poll 20 ready "$id" || fail "the daemon did not answer"
output=$(
  docker exec -u dev "$id" id -u 2>&1
  docker logs "$id" 2>&1
) || true
expect_line "1000"
expect_text "expected decimal uid and gid up to 4294967294"
docker restart "$id" >/dev/null
poll 20 ready "$id" || fail "the daemon did not answer after a restart"
# The command of the container, sleep, runs as dev after the restart too.
output=$(docker exec "$id" sh -c 'for p in /proc/[0-9]*; do
  case "$(tr "\0" " " <"$p/cmdline" 2>/dev/null)" in
    */sleep\ infinity\ ) awk "/^Uid:/ { print \$2 }" "$p/status" ;;
  esac; done' 2>&1) || true
expect_line "1000"
docker rm -f "$id" >/dev/null

test_case "dev cannot change the files that decide trust"
run -- sh -c 'for f in /etc/passwd /etc/group /etc/nix/nix.conf /etc/nix/new.conf /nix/var/nix/db/new /nix/var/nix/gcroots/new; do touch "$f" 2>/dev/null && echo "wrote $f"; done; stat -c "%U:%G %a" /nix/store; echo checked'
expect_line "checked"
expect_line "root:nixbld 1775"
expect_no_text "wrote"

test_case "builds work with only the documented capabilities"
run --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add SETUID --cap-add SETGID \
  -v "$tests/../fixture:/fixture:ro" -- sh -c 'cat "$(nix-build --no-out-link /fixture/uid.nix)"'
grep -qxE '300[0-9][0-9]' <<<"$output" || fail "the build failed with these capabilities"

test_case "stdin from a pipe is readable by dev"
output=$(echo from-stdin | timeout 60 docker run --rm -i "$IMAGE" sh -c 'cat /dev/stdin' 2>&1) || true
expect_line "from-stdin"

test_case "every link into the store outside the store is kept by GC"
id=$(start)
poll 20 ready "$id" || fail "the daemon did not answer"
docker exec "$id" nix-collect-garbage >/dev/null 2>&1 || fail "garbage collection failed"
output=$(docker exec "$id" sh -c 'find / -xdev -path /nix/store -prune -o -type l -lname "/nix/store/*" -print | while read -r link; do [ -e "$link" ] || echo "dangling $link"; done; echo checked' 2>&1) || true
expect_line "checked"
expect_no_text "dangling"
docker rm -f "$id" >/dev/null
