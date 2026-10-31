# shellcheck shell=bash
# Entrypoint of the image (FY-0005): adapts `dev` to the owner of the project,
# runs the Nix daemon supervised, and runs the command as `dev` under tini.
#
# Of the environment, it reads DEV_UID and DEV_GID; the Nix daemon gets a
# fixed environment of its own. The paths below are fixed; the unit tests
# change them after sourcing this file.

user=dev
home=/home/dev
passwd_file=/etc/passwd
group_file=/etc/group
socket=/nix/var/nix/daemon-socket/socket
daemon_log=/var/log/nix-daemon.log
ca_file=/etc/ssl/certs/ca-certificates.crt
# PATH of the command run as dev, and of the Nix processes run as root. Root's
# is fixed: not the container's, and never dev's profile, which dev controls.
# The build sets entrypoint_tools to the tools of the entrypoint
# (nix/entrypoint.nix).
dev_path=$home/.nix-profile/bin:/bin:/usr/bin
daemon_path=${entrypoint_tools:+$entrypoint_tools:}/bin:/usr/bin
# Proxies of the container engine reach the daemon, which downloads.
proxy_vars=(http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY)

# The daemon has this long to answer, checked this often (seconds).
daemon_timeout=10
daemon_poll=0.1
# The supervisor gives up after this many exits in a row, each this soon
# after its start (seconds), and waits between restarts.
max_quick_exits=5
quick_exit_seconds=60
restart_delay=1

# The largest uid and gid: 4294967295 means "unchanged" to setresuid, and
# larger values wrap around to 0.
max_id=4294967294
decimal_pattern='^[0-9]{1,10}$'

log() { printf 'entrypoint: %s\n' "$*" >&2; }

# field FILE NAME N: prints field N of the entry NAME of a passwd or group file.
field() { awk -F: -v name="$2" -v n="$3" '$1 == name { print $n; exit }' "$1"; }

# owner_name FILE ID: prints the name of the entry with id ID, if any.
owner_name() { awk -F: -v id="$2" '$3 == id { print $1; exit }' "$1"; }

# Seams for the tests.
is_mount() { mountpoint -q -- "$1"; }
owner_of() { stat -c '%u %g' -- "$1"; }
# change_owner OWNER: gives the NUL-separated paths on stdin to OWNER, a uid
# or :gid.
change_owner() { xargs -0 -r chown -h -- "$1"; }

# decimal VALUE: prints VALUE as a decimal number, or fails if it is not one
# or does not fit a uid.
decimal() {
  local value=$1
  [[ $value =~ $decimal_pattern ]] || return 1
  (($((10#$value)) <= max_id)) || return 1
  printf '%d\n' "$((10#$value))"
}

# --- the identity of dev ------------------------------------------------------

# current_identity: prints the uid and gid of `dev` in passwd.
current_identity() {
  awk -F: -v name="$user" '$1 == name { print $3, $4; exit }' "$passwd_file"
}

# wanted_identity: prints the uid and gid `dev` should have: DEV_UID and DEV_GID
# when given, else the owner of the working directory when it is a mount point
# not owned by root, else the current ones.
wanted_identity() {
  local owner
  if [[ -n ${DEV_UID-} ]]; then
    checked_identity "$DEV_UID" "${DEV_GID:-$DEV_UID}"
    return
  fi
  owner=$(mount_owner)
  if [[ -n $owner ]]; then
    checked_identity "${owner%% *}" "${owner##* }"
  else
    current_identity
  fi
}

# mount_owner: prints the uid and gid of the working directory when it is a
# mount point not owned by root.
mount_owner() {
  local owner
  if ! [[ -x $PWD ]] || ! owner=$(owner_of "$PWD"); then
    log "cannot inspect the working directory $PWD; the container may lack the capability DAC_OVERRIDE"
  elif is_mount "$PWD" && [[ ${owner%% *} != 0 ]]; then
    printf '%s\n' "$owner"
  fi
}

# checked_identity UID GID: prints UID and GID when `dev` may have them, else
# the current identity. A GID of another group keeps the current gid.
checked_identity() {
  local uid=$1 gid=$2 owner
  if ! uid=$(decimal "$uid") || ! gid=$(decimal "$gid"); then
    keep_identity "ignoring '${DEV_UID-}:${DEV_GID-}': expected decimal uid and gid up to $max_id"
  elif ((uid == 0 || gid == 0)); then
    keep_identity "ignoring uid or gid 0"
  elif owner=$(other_owner "$passwd_file" "$uid") && [[ -n $owner ]]; then
    keep_identity "ignoring uid $uid: it belongs to '$owner'"
  else
    gid=$(kept_gid "$gid")
    printf '%s %s\n' "$uid" "$gid"
  fi
}

# keep_identity MESSAGE: logs why `dev` stays as it is, and prints its identity.
keep_identity() {
  local message=$1
  log "$message"
  current_identity
}

# other_owner FILE ID: prints the name of the entry with id ID in a passwd or
# group file, if there is one other than `dev`.
other_owner() {
  local file=$1 id=$2 owner
  owner=$(owner_name "$file" "$id")
  if [[ -n $owner && $owner != "$user" ]]; then printf '%s\n' "$owner"; fi
}

# kept_gid GID: prints GID, or the current gid of `dev` when GID belongs to
# another group.
kept_gid() {
  local gid=$1 owner identity old_gid
  owner=$(other_owner "$group_file" "$gid")
  if [[ -z $owner ]]; then
    printf '%s\n' "$gid"
    return
  fi
  identity=$(current_identity)
  read -r _ old_gid <<<"$identity"
  log "keeping gid $old_gid: gid $gid belongs to group '$owner'"
  printf '%s\n' "$old_gid"
}

# --- changing dev -------------------------------------------------------------

# set_identity UID GID: gives `dev` this uid and gid, and its files on the
# home directory's own file system; mount points and mounted files below it
# belong to the host and are left alone. The files change first, then group,
# and passwd last: passwd decides whether the files still have to change, so
# a start that fails in between is completed by the next.
set_identity() {
  local uid=$1 gid=$2 identity
  has_identity "$uid" "$gid" && return 0
  identity=$(current_identity)
  if [[ $identity != "$uid $gid" ]]; then
    own_home "$identity" "$uid" "$gid" || return 1
  fi
  update_accounts "$uid" "$gid" || return 1
  log "user '$user' is now $uid:$gid"
}

# has_identity UID GID: passwd and group both give `dev` this uid and gid.
has_identity() {
  local uid=$1 gid=$2 identity
  identity=$(current_identity)
  [[ $identity == "$uid $gid" && $(field "$group_file" "$user" 3) == "$gid" ]]
}

# update_accounts UID GID: gives `dev` this uid and gid in group and passwd.
update_accounts() {
  local uid=$1 gid=$2
  if ! rewrite_group "$gid" || ! rewrite_passwd "$uid" "$gid" || ! has_identity "$uid" "$gid"; then
    log "cannot change '$user' to $uid:$gid in $passwd_file and $group_file"
    return 1
  fi
}

# rewrite_group GID: gives the group `dev` this gid, unless it has it.
rewrite_group() {
  local gid=$1
  [[ $(field "$group_file" "$user" 3) != "$gid" ]] || return 0
  sed -i -e "s/^$user:\([^:]*\):[0-9]*:/$user:\1:$gid:/" "$group_file"
}

# rewrite_passwd UID GID: gives the user `dev` this uid and gid.
rewrite_passwd() {
  local uid=$1 gid=$2
  sed -i -e "s/^$user:\([^:]*\):[0-9]*:[0-9]*:/$user:\1:$uid:$gid:/" "$passwd_file"
}

# own_home "OLD_UID OLD_GID" UID GID: gives the files of `dev` under home to
# UID:GID, unless home itself is mounted: then all of it belongs to the host.
own_home() {
  local old=$1 uid=$2 gid=$3 old_uid old_gid home_dev
  if is_mount "$home"; then
    log "$home is a mount point: its files keep their owner"
    return 0
  fi
  read -r old_uid old_gid <<<"$old"
  home_dev=$(stat -c %d -- "$home")
  # Owner and group apart: a file of root in the group of dev stays root's.
  if ! own_files -user "$old_uid" "$uid" "$home_dev" ||
    ! own_files -group "$old_gid" ":$gid" "$home_dev"; then
    log "cannot give the files of '$user' under $home to $uid:$gid"
    return 1
  fi
}

# own_files TEST OLD NEW DEVICE: gives the files under home that match
# `find TEST OLD` and are on DEVICE to NEW. chown -h does not follow a link at
# the end of a path, but a process of dev that replaces a directory of the
# path with a link while the container starts could redirect it; chown -R
# would not, but it would also cross into mounted files of the host.
own_files() {
  local test=$1 old=$2 new=$3 device=$4
  find "$home" -xdev "$test" "$old" -printf '%D\0%p\0' | paths_on "$device" | change_owner "$new"
}

# paths_on DEVICE: of the NUL-separated pairs of device and path on stdin,
# prints the paths on DEVICE, NUL-separated.
paths_on() {
  local device=$1
  awk -v RS='\0' -v ORS='\0' -v device="$device" 'NR % 2 { on = ($0 == device); next } on'
}

# give_streams UID GID: gives stdin, stdout and stderr to the user when the
# container engine made them, so that it can reopen them as /dev/stdout and
# /dev/stderr after dropping root, as nix-direnv does: anonymous pipes and
# sockets, such as the FIFOs of the engine, and the container's terminal,
# which keeps its group (tty). Files, named FIFOs and /dev/null are left
# alone: they may belong to the host.
give_streams() {
  local uid=$1 gid=$2 fd stream target
  for fd in 0 1 2; do
    # The entrypoint's own descriptors: /proc/self would be those of readlink
    # and chown.
    stream=/proc/$$/fd/$fd
    target=$(readlink "$stream" 2>/dev/null) || continue
    case $target in
      pipe:* | socket:*) chown "$uid:$gid" "$stream" 2>/dev/null || true ;;
      /dev/pts/* | /dev/console)
        if [[ -c $stream ]]; then chown "$uid" "$stream" 2>/dev/null || true; fi
        ;;
    esac
  done
}

# --- the Nix daemon -----------------------------------------------------------

# as_root [NAME=VALUE...] COMMAND...: runs a Nix process of root with an
# environment of its own. Settings such as NIX_CONFIG in the container's
# environment must not reach root, which Nix trusts (FY-0005); only the
# proxies of the engine do.
as_root() {
  local vars=(PATH="$daemon_path" HOME=/root NIX_SSL_CERT_FILE="$ca_file") name
  for name in "${proxy_vars[@]}"; do
    if [[ -n ${!name-} ]]; then vars+=("$name=${!name}"); fi
  done
  env -i "${vars[@]}" "$@"
}

# supervise: runs the Nix daemon and restarts it when it exits; gives up after
# a few quick exits in a row.
supervise() {
  local exits=0 started
  while ((exits < max_quick_exits)); do
    started=$SECONDS
    as_root nix-daemon >>"$daemon_log" 2>&1 || true
    if ((SECONDS - started >= quick_exit_seconds)); then exits=0; fi
    exits=$((exits + 1))
    log "nix-daemon exited, restarting (see $daemon_log)"
    sleep "$restart_delay"
  done
  log "nix-daemon exited $exits times in a row, giving up"
}

# writable DIR: DIR exists and a file can be created in it; on a read-only
# file system, root passes `-w` but cannot write.
writable() {
  local dir=$1 probe
  mkdir -p -- "$dir" 2>/dev/null &&
    probe=$(mktemp -p "$dir" .entrypoint.XXXXXX 2>/dev/null) &&
    rm -f -- "$probe"
}

# start_daemon: starts the supervised daemon and waits until it answers.
start_daemon() {
  if ! writable "$(dirname -- "$socket")" || ! rm -f -- "$socket" 2>/dev/null; then
    log "/nix is not writable: the Nix daemon is not started"
    return 0
  fi
  if ! : >>"$daemon_log" 2>/dev/null; then
    log "cannot write $daemon_log; the Nix daemon logs to the container log"
    daemon_log=/proc/$$/fd/2
  fi
  supervise &
  wait_for_daemon
}

# wait_for_daemon: waits until the daemon answers, or reports that it does not.
wait_for_daemon() {
  local deadline=$((SECONDS + daemon_timeout))
  until daemon_answers; do
    if ((SECONDS >= deadline)); then
      log "the Nix daemon did not answer within $daemon_timeout s (see $daemon_log)"
      return 0
    fi
    sleep "$daemon_poll"
  done
}

# daemon_answers: the daemon listens and answers a client of root.
daemon_answers() {
  [[ -S $socket ]] && as_root NIX_REMOTE=daemon nix store info >/dev/null 2>&1
}

# --- running the command ------------------------------------------------------

# runnable UID GID: the identity the command may run as: decimal, not root.
runnable() {
  local uid=$1 gid=$2
  decimal "$uid" >/dev/null && decimal "$gid" >/dev/null && ((uid != 0 && gid != 0))
}

main() {
  if [[ $(id -u) != 0 ]]; then run_unprivileged "$@"; fi
  stop_on_signals
  local identity uid gid
  identity=$(wanted_identity)
  read -r uid gid <<<"$identity"
  set_identity "$uid" "$gid" || exit 1
  start_daemon
  identity=$(current_identity)
  read -r uid gid <<<"$identity"
  # Never root: whatever passwd says, the command must run as dev.
  if ! runnable "$uid" "$gid"; then
    log "refusing to run the command as '$user' with uid $uid and gid $gid"
    exit 1
  fi
  give_streams "$uid" "$gid"
  exec_as_dev "$uid" "$gid" "$@"
}

# stop_on_signals: ends the entrypoint on SIGTERM and SIGINT until tini takes
# over. As PID 1 without a handler, bash ignores them, so a container stopped
# right after it starts would wait for SIGKILL.
stop_on_signals() {
  trap 'exit 143' TERM
  trap 'exit 130' INT
}

# run_unprivileged COMMAND...: runs the command as it is, without the daemon.
run_unprivileged() {
  log "started as uid $(id -u) instead of 0: the Nix daemon is not running."
  log "start the container as root (the default); it switches to '$user' itself."
  exec "$@"
}

# exec_as_dev UID GID COMMAND...: runs the command as `dev` under tini.
exec_as_dev() {
  local uid=$1 gid=$2 tini setpriv
  shift 2
  # Resolved while PATH is still root's; then dev's PATH for the command.
  tini=$(command -v tini)
  setpriv=$(command -v setpriv)
  export HOME=$home USER=$user LOGNAME=$user PATH=$dev_path
  exec "$tini" -s -g -- "$setpriv" --reuid="$uid" --regid="$gid" --init-groups -- "$@"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
