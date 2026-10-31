# shellcheck shell=bash disable=SC2016 # commands run in the container
# Smoke tests of identity and start-up (FY-0005). Sourced by scripts/smoke.sh
# after tests/smoke/lib.sh. Inputs (environment): IMAGE, WORK (a scratch
# directory on the runner).

# --- the user and its shell ---------------------------------------------------

test_case "runs the command as dev with its home"
run -- bash -c 'echo "$(id -u):$(id -g) $HOME $USER $LOGNAME"'
expect_line "1000:1000 /home/dev dev dev"

test_case "has the tools by name"
run -- bash -c 'for t in nix direnv bash ls find diff grep sed awk tar gzip xz bzip2 zstd less ps which mount getent curl git ssh tini; do command -v "$t" >/dev/null || echo "missing $t"; done; echo done'
expect_line "done"
expect_no_text "missing"

test_case "interactive and login shells have the direnv hook"
run -- bash -ic 'type -t _direnv_hook'
expect_line "function"
run -- bash -lic 'type -t _direnv_hook'
expect_line "function"

test_case "docker exec without a user is root"
id=$(start)
poll 20 ready "$id" || fail "the daemon did not answer"
output=$(docker exec "$id" sh -c 'id -u' 2>&1) || true
expect_line "0"
docker rm -f "$id" >/dev/null

# --- init, signals, restarts ----------------------------------------------------

test_case "tini is PID 1 and reaps orphans"
id=$(start)
poll 20 ready "$id" || fail "the daemon did not answer"
docker exec -u dev "$id" sh -c '(sleep 0.3 &) ; (sleep 0.3 &) ; (sleep 0.3 &)'
zombies() {
  output=$(docker exec "$id" sh -c 'z=0; for s in /proc/[0-9]*/stat; do read -r _ _ state _ <"$s" 2>/dev/null && [ "$state" = Z ] && z=$((z+1)); done; echo $z; tr "\0" " " </proc/1/cmdline' 2>&1)
  [[ $(head -n 1 <<<"$output") == 0 ]]
}
sleep 1
poll 10 zombies || fail "zombies left"
expect_text "tini"

test_case "stops within 5 seconds"
started=$SECONDS
docker stop "$id" >/dev/null
((SECONDS - started <= 5)) || fail "docker stop took $((SECONDS - started)) s"

test_case "starts again"
docker start "$id" >/dev/null
poll 20 ready "$id" || fail "the daemon did not answer after a restart"
docker rm -f "$id" >/dev/null

test_case "restarts the Nix daemon after it is killed"
id=$(start)
poll 20 ready "$id" || fail "the daemon did not answer"
for round in 1 2 3; do
  docker exec "$id" sh -c 'for p in /proc/[0-9]*; do [ "$(tr "\0" " " <"$p/cmdline" 2>/dev/null)" = "nix-daemon " ] && kill -9 "${p#/proc/}"; done; true'
  sleep 1
  poll 20 ready "$id" || fail "the daemon did not come back after kill $round"
done
output=$(docker logs "$id" 2>&1) || true
expect_text "nix-daemon exited, restarting"
docker rm -f "$id" >/dev/null

# --- adapting dev ----------------------------------------------------------------

test_case "DEV_UID and DEV_GID"
run -e DEV_UID=1001 -e DEV_GID=1005 -- sh -c 'id -u; id -g'
expect_line "1001"
expect_line "1005"
expect_text "user 'dev' is now 1001:1005"

test_case "rejects DEV_UID of another user"
run -e DEV_UID=30001 -- id -u
expect_line "1000"
expect_text "ignoring uid 30001: it belongs to 'nixbld1'"

test_case "adopts the owner of a mounted project"
mkdir -p "$WORK/project"
sudo chown 1002:1002 "$WORK/project"
run -v "$WORK/project:/home/dev/project" -w /home/dev/project -- sh -c 'id -u; touch created && echo written'
expect_line "1002"
expect_line "written"

test_case "leaves host files under home alone"
mkdir -p "$WORK/host"
touch "$WORK/host/file" "$WORK/gitconfig"
sudo chown -R 1000:1000 "$WORK/host" "$WORK/gitconfig"
run -e DEV_UID=1003 -v "$WORK/host:/home/dev/host" -v "$WORK/gitconfig:/home/dev/.gitconfig" -- id -u
expect_line "1003"
[[ $(stat -c %u:%g "$WORK/host" "$WORK/host/file" "$WORK/gitconfig" | sort -u) == 1000:1000 ]] ||
  fail "host files changed owner: $(stat -c '%n %u:%g' "$WORK/host" "$WORK/host/file" "$WORK/gitconfig")"

test_case "does not adopt a working directory that is not a mount point"
run -w /tmp -- id -u
expect_line "1000"

test_case "a read-only root fails clearly when dev must change"
run --read-only --tmpfs /tmp -e DEV_UID=1001 -- id -u
expect_text "cannot give the files of 'dev' under /home/dev to 1001:1001"

test_case "started without root it warns and runs the command"
run --user 1000 -- sh -c 'echo ran'
expect_text "started as uid 1000 instead of 0"
expect_line "ran"

test_case "ignores variables other than DEV_UID and DEV_GID"
run -e passwd_file=/tmp/passwd -e home=/tmp -e user=root -- sh -c 'id -un; echo "$HOME"'
expect_line "dev"
expect_line "/home/dev"

test_case "dev can reopen stdout and stderr"
run -- sh -c 'echo to-stdout >/dev/stdout; echo to-stderr >/dev/stderr; stat -c %U /dev/null'
expect_line "to-stdout"
expect_line "to-stderr"
expect_line "root"

# --- capabilities ----------------------------------------------------------------

test_case "works with only CHOWN, DAC_OVERRIDE, FOWNER, SETUID and SETGID"
run --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add SETUID --cap-add SETGID \
  -v "$WORK/project:/home/dev/project" -w /home/dev/project -- sh -c 'id -u; nix store info >/dev/null && echo nix-ok; touch created2 && echo written'
expect_line "1002"
expect_line "nix-ok"
expect_line "written"

test_case "without DAC_OVERRIDE it says why dev was not adapted"
run --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID \
  -v "$WORK/project:/home/dev/project" -w /home/dev/project -- id -u
expect_text "cannot inspect the working directory"
