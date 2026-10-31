# shellcheck shell=bash disable=SC2016,SC2034,SC2154 # container commands; shared variables
# Smoke tests of the boundary between dev and root (FY-0005), from the code
# audit. Sourced by scripts/smoke.sh after tests/smoke/lib.sh. Inputs
# (environment): IMAGE, WORK, tests.

test_case "root never runs programs from dev's profile"
start_ready id
docker exec -u dev "$id" sh -c '
  rm -rf "$HOME/.nix-profile" && mkdir -p "$HOME/.nix-profile/bin" &&
  for tool in sh bash direnv nix id; do
    printf "#!/bin/sh\ntouch /tmp/ran-from-profile\nexit 0\n" >"$HOME/.nix-profile/bin/$tool"
    chmod +x "$HOME/.nix-profile/bin/$tool"
  done'
output=$(docker exec "$id" sh -c 'id -u')
expect_line "0"
# Only whether the shells ran a program of the profile matters.
docker exec "$id" bash -ic true >/dev/null 2>&1 || true
docker exec "$id" bash -lc true >/dev/null 2>&1 || true
output=$(docker exec "$id" sh -c 'ls /tmp/ran-from-profile 2>&1 || echo clean')
expect_line "clean"
output=$(docker exec -u dev "$id" bash -ic 'command -v direnv')
expect_text "/home/dev/.nix-profile/bin/direnv"
remove "$id"

test_case "NIX_CONFIG of the container does not reach the daemon"
run -e NIX_CONFIG='trusted-users = root dev' -- nix store info
expect_line "Trusted: 0"

test_case "rejects a DEV_UID that does not fit a uid, also after a restart"
start_ready id -e DEV_UID=4294967296
output=$(
  docker exec -u dev "$id" id -u 2>&1
  docker logs "$id" 2>&1
)
expect_line "1000"
expect_text "expected decimal uid and gid up to 4294967294"
docker restart "$id" >/dev/null
poll "$daemon_timeout" ready "$id" || fail "the daemon did not answer after a restart"
# The command of the container, sleep, runs as dev after the restart too. Its
# first word is sleep itself; the entrypoint and tini only end with it.
command_uid() {
  output=$(docker exec "$id" sh -c 'for p in /proc/[0-9]*; do
    set -- $(cat "$p/cmdline" 2>/dev/null | tr "\0" " ")
    [ "${1##*/}" = sleep ] && [ "${2-}" = infinity ] && awk "/^Uid:/ { print \$2 }" "$p/status" 2>/dev/null
  done' 2>/dev/null) || true
  # Processes may end while the loop reads /proc: wait for the uid itself.
  [[ $output =~ ^[0-9]+$ ]]
}
poll 20 command_uid || fail "the command did not start after the restart"
expect_line "1000"
remove "$id"

test_case "dev cannot change the files that decide trust"
run -- sh -c 'for f in /etc/passwd /etc/group /etc/nix/nix.conf /etc/nix/new.conf /nix/var/nix/db/new /nix/var/nix/gcroots/new; do touch "$f" 2>/dev/null && echo "wrote $f"; done; stat -c "%U:%G %a" /nix/store; echo checked'
expect_line "checked"
expect_line "root:nixbld 1775"
expect_no_text "wrote"

test_case "builds work with only the documented capabilities"
run "${only_documented_caps[@]}" -v "$tests/../fixture:/fixture:ro" -- sh -c 'cat "$(nix-build --no-out-link /fixture/uid.nix)"'
expect_build_user

test_case "stdin from a pipe is readable by dev"
output=$(echo from-stdin | timeout 60 docker run --rm -i "$IMAGE" sh -c 'cat /dev/stdin' 2>&1)
expect_line "from-stdin"

test_case "every link into the store outside the store is kept by GC"
start_ready id
collect_garbage "$id"
output=$(docker exec "$id" sh -c 'find / -xdev -path /nix/store -prune -o -type l -lname "/nix/store/*" -print | while read -r link; do [ -e "$link" ] || echo "dangling $link"; done; echo checked' 2>&1)
expect_line "checked"
expect_no_text "dangling"
remove "$id"

test_case "a mounted home keeps the owner of its files"
mkdir -p "$WORK/home/old"
touch "$WORK/home/old/file"
sudo chown 1004:1004 "$WORK/home"
sudo chown -R 1000:1000 "$WORK/home/old"
run -v "$WORK/home:/home/dev" -- id -u
expect_line "1004"
expect_text "/home/dev is a mount point: its files keep their owner"
[[ $(stat -c %u:%g "$WORK/home/old" "$WORK/home/old/file" | sort -u) == 1000:1000 ]] ||
  fail "files of the old uid changed owner: $(stat -c '%n %u:%g' "$WORK/home/old" "$WORK/home/old/file")"

test_case "the daemon gets the proxies but not the settings of the container"
# Nothing listens at the proxy; the daemon only has to start.
start_ready id -e https_proxy=http://proxy.invalid:3128 -e NIX_CONFIG='trusted-users = root dev' -e XDG_CONFIG_HOME=/tmp
output=$(docker exec "$id" sh -c 'for p in /proc/[0-9]*; do
  [ "$(tr "\0" " " <"$p/cmdline" 2>/dev/null)" = "nix-daemon " ] && tr "\0" "\n" <"$p/environ"
done; true' 2>&1)
expect_line "https_proxy=http://proxy.invalid:3128"
expect_no_text "NIX_CONFIG"
expect_no_text "XDG_CONFIG_HOME"
remove "$id"

test_case "dev can reopen the terminal of docker run -t"
run -t -- sh -c 'echo to-stderr >/dev/stderr && stat -c %U "$(readlink /proc/self/fd/2)"'
# A terminal ends lines with CR LF.
output=${output//$'\r'/}
expect_line "to-stderr"
expect_line "dev"

test_case "a read-only /nix runs the command without the daemon"
run --read-only --tmpfs /tmp -- sh -c 'echo ran'
expect_text "/nix is not writable: the Nix daemon is not started"
expect_line "ran"
expect_no_text "did not answer"
