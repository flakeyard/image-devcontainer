# shellcheck shell=bash disable=SC2016,SC2154 # commands run in the container; id and the settings come from lib.sh
# Smoke tests of identity and start-up (ADR-0001). Sourced by scripts/smoke.sh
# after tests/smoke/lib.sh. Inputs (environment): IMAGE, WORK (a scratch
# directory on the runner).

# Seconds a container has to end after SIGTERM, well below the 10 s after
# which docker stop sends SIGKILL.
stop_timeout=5

# no_zombies ID: no process of the container is a zombie; output holds their
# number and the command line of PID 1.
no_zombies() {
  local id=$1
  output=$(docker exec -i "$id" sh -s <"$probes/zombies.sh" 2>&1)
  [[ $(head -n 1 <<<"$output") == 0 ]]
}

# --- the user and its shell ---------------------------------------------------

test_case "runs the command as dev with its home"
run -- bash -c 'echo "$(id -u):$(id -g) $HOME $USER $LOGNAME"'
expect_line "1000:1000 /home/dev dev dev"

test_case "has the tools by name, and the client of OpenSSH only"
run -i -- bash -s <"$probes/tools.sh"
expect_line "done"
expect_no_text "missing"
expect_no_text "ssh-server"

test_case "/usr/bin/bash is the file of /bin/bash and /bin/sh"
run -- readlink -f /bin/bash /usr/bin/bash /bin/sh
[[ $(wc -l <<<"$output") == 3 && $(sort -u <<<"$output" | wc -l) == 1 && $output == /nix/store/*/bin/bash* ]] ||
  fail "not one bash"

test_case "dev runs /usr/bin/bash with uid 1000 and other uids"
run -- /usr/bin/bash -c 'echo "ran as $(id -u)"'
expect_line "ran as 1000"
run -e DEV_UID=1001 -- /usr/bin/bash -c 'echo "ran as $(id -u)"'
expect_line "ran as 1001"
run --user 4321 -- /usr/bin/bash -c 'echo "ran as $(id -u)"'
expect_line "ran as 4321"

test_case "/usr/bin/bash -p ignores BASH_ENV and exported functions, and plain bash does not"
printf '%s\n' 'echo sourced' >"$WORK/usr-bin-bash-env"
bash_env=(-v "$WORK/usr-bin-bash-env:/bash-env:ro" -e BASH_ENV=/bash-env -e 'BASH_FUNC_probe%%=() { echo imported; }')
run "${bash_env[@]}" -- /usr/bin/bash -p -c 'probe 2>/dev/null || echo clean'
expect_line "clean"
expect_no_text "sourced"
expect_no_text "imported"
run "${bash_env[@]}" -- /usr/bin/bash -c probe
expect_line "sourced"
expect_line "imported"

test_case "the image root has no entries named after store paths"
run -- ls -A /
! grep -qE '^[0-9a-z]{32}-' <<<"$output" || fail "store path names in /: $output"

test_case "interactive and login shells have the direnv hook"
run -- bash -ic 'type -t _direnv_hook'
expect_line "function"
run -- bash -lic 'type -t _direnv_hook'
expect_line "function"

test_case "docker exec without a user is root"
start_ready id
output=$(docker exec "$id" sh -c 'id -u' 2>&1)
expect_line "0"
remove "$id"

# --- init, signals, restarts ----------------------------------------------------

test_case "tini is PID 1 and reaps orphans"
start_ready id
docker exec -u dev "$id" sh -c '(sleep 0.3 &) ; (sleep 0.3 &) ; (sleep 0.3 &)'
sleep 1
poll 10 no_zombies "$id" || fail "zombies left"
expect_text "tini"
remove "$id"

test_case "stops within 5 seconds"
start_ready id
started=$SECONDS
docker stop "$id" >/dev/null
((SECONDS - started <= stop_timeout)) || fail "docker stop took $((SECONDS - started)) s"
remove "$id"

# stops ID: the container ends within stop_timeout seconds.
stops() {
  local id=$1
  timeout "$stop_timeout" docker wait "$id" >/dev/null
}

test_case "stops on SIGTERM right after it starts"
id=$(start)
docker kill -s TERM "$id" >/dev/null
stops "$id" || fail "still running $stop_timeout s after SIGTERM"
remove "$id"

# The exit status of a process killed by SIGKILL.
killed_status=137

# term_at_handover ID: sends SIGTERM to PID 1 of the container the moment the
# entrypoint becomes the command; output holds the name of the child then.
# The probe runs in the container, so the kernel kills it with the container
# when that stops before the probe ends: it fails on other statuses only.
term_at_handover() {
  local id=$1 status=0
  output=$(docker exec -i "$id" sh -s <"$probes/term-at-handover.sh" 2>&1) || status=$?
  ((status == 0 || status == killed_status))
}

# Before tini was PID 1, the entrypoint exec'd it here, and the kernel
# dropped a SIGTERM that reached PID 1 during that exec.
test_case "stops on SIGTERM while the entrypoint becomes the command"
for round in 1 2 3; do
  id=$(start)
  term_at_handover "$id" || fail "round $round: the probe failed"
  stops "$id" || fail "round $round: still running $stop_timeout s after SIGTERM to $output"
  remove "$id"
done

test_case "the Nix daemon is not in the process group of the command"
start_ready id
# The groups of the child of tini, the command, and of the daemon.
output=$(docker exec "$id" sh -c 'ps -o pgid= -p "$(cut -d " " -f 1 /proc/1/task/1/children)"; ps -o pgid= -C nix-daemon')
[[ $(sort -u <<<"$output" | wc -l) == 2 ]] || fail "the same group, or none"
remove "$id"

test_case "starts again"
start_ready id
docker stop "$id" >/dev/null
docker start "$id" >/dev/null
poll "$daemon_timeout" ready "$id" || fail "the daemon did not answer after a restart"
remove "$id"

test_case "restarts the Nix daemon after it is killed"
start_ready id
for round in 1 2 3; do
  docker exec -i "$id" sh -s <"$probes/kill-daemon.sh"
  sleep 1
  poll "$daemon_timeout" ready "$id" || fail "the daemon did not come back after kill $round"
done
output=$(docker logs "$id" 2>&1)
expect_text "nix-daemon exited, restarting"
remove "$id"

test_case "restarts the Nix daemon under a terminal that stops background writes"
start_ready id -t
# tini has the terminal of the container as its input.
docker exec "$id" sh -c 'stty tostop </proc/1/fd/0'
docker exec -i "$id" sh -s <"$probes/kill-daemon.sh"
sleep 1
poll "$daemon_timeout" ready "$id" || fail "the daemon did not come back"
# The inputs of the supervisor, /dev/null, and of its pipeline, a pipe: the
# processes left that still run the entrypoint.
output=$(docker exec "$id" sh -c 'for pid in $(pgrep -x entrypoint); do readlink "/proc/$pid/fd/0"; done')
expect_line /dev/null
! grep -qE '^/dev/(pts|console|tty)' <<<"$output" || fail "the supervisor reads from a terminal"
remove "$id"

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

test_case "root's bash ignores BASH_ENV, exported functions and SHELLOPTS"
printf '%s\n' 'touch /tmp/sourced' >"$WORK/bash-env"
# The function id would tell the entrypoint it is not root, so that it runs
# the command as root; the command's shell imports it too, so the uids come
# from /proc.
run -v "$WORK/bash-env:/bash-env:ro" -e BASH_ENV=/bash-env -e 'BASH_FUNC_id%%=() { echo 1000; }' \
  -e SHELLOPTS=xtrace -- sh -c 'grep ^Uid: /proc/self/status; ls /tmp/sourced 2>/dev/null || echo clean'
expect_line $'Uid:\t1000\t1000\t1000\t1000'
expect_line "clean"
# A line that only the trace of the entrypoint has.
expect_no_text "dev_path="

test_case "dev can reopen stdout and stderr"
run -- sh -c 'echo to-stdout >/dev/stdout; echo to-stderr >/dev/stderr; stat -c %U /dev/null'
expect_line "to-stdout"
expect_line "to-stderr"
expect_line "root"

# --- volumes -------------------------------------------------------------------

# The volume targets that the README supports, restated as its oracle.
volume_targets=(.cache .local/share .vscode-server)

# new_volumes TARGET...: docker arguments that mount a new volume at each
# TARGET under /home/dev. Anonymous volumes start like new named ones, and
# run --rm removes them.
new_volumes() {
  local target
  for target; do
    printf '%s\n' --mount "type=volume,target=/home/dev/$target"
  done
}

test_case "dev can write to new volumes at the supported targets"
mapfile -t volumes < <(new_volumes "${volume_targets[@]}")
run "${volumes[@]}" -- sh -c 'for target; do touch "$HOME/$target/file" && echo "written $target"; done' sh "${volume_targets[@]}"
for target in "${volume_targets[@]}"; do
  expect_line "written $target"
done

test_case "a new volume keeps uid 1000 when dev gets another uid"
mapfile -t volumes < <(new_volumes .cache)
run -e DEV_UID=1001 "${volumes[@]}" -- stat -c %u /home/dev/.cache
expect_line "1000"

# --- capabilities ----------------------------------------------------------------

test_case "works with only CHOWN, DAC_OVERRIDE, FOWNER, SETUID and SETGID"
run "${only_documented_caps[@]}" -v "$WORK/project:/home/dev/project" -w /home/dev/project -- sh -c 'id -u; nix store info >/dev/null && echo nix-ok; touch created2 && echo written'
expect_line "1002"
expect_line "nix-ok"
expect_line "written"

test_case "without DAC_OVERRIDE it says why dev was not adapted"
run --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID \
  -v "$WORK/project:/home/dev/project" -w /home/dev/project -- id -u
expect_text "cannot inspect the working directory"
