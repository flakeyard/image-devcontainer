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
daemon_wait=100 # tenths of a second
# PATH of the command run as dev, and of the daemon run as root. The daemon
# must not see dev's profile: dev controls it.
dev_path=$home/.nix-profile/bin:/bin:/usr/bin
daemon_path=$PATH

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
# or does not fit a uid: 4294967295 means "unchanged" to setresuid, and larger
# values wrap around to 0.
decimal() {
  [[ $1 =~ ^[0-9]{1,10}$ ]] || return 1
  (($((10#$1)) <= 4294967294)) || return 1
  printf '%d\n' "$((10#$1))"
}

# wanted_identity: prints the uid and gid `dev` should have: DEV_UID and DEV_GID
# when given, else the owner of the working directory when it is a mount point
# not owned by root, else the current ones.
wanted_identity() {
  local old_uid old_gid uid gid owner
  old_uid=$(field "$passwd_file" "$user" 3)
  old_gid=$(field "$passwd_file" "$user" 4)
  uid=${DEV_UID-} gid=${DEV_GID-}
  if [[ -z $uid ]]; then
    if ! [[ -x $PWD ]] || ! owner=$(owner_of "$PWD"); then
      log "cannot inspect the working directory $PWD; the container may lack the capability DAC_OVERRIDE"
    elif is_mount "$PWD" && [[ ${owner%% *} != 0 ]]; then
      uid=${owner%% *} gid=${owner##* }
    fi
  fi
  if [[ -z $uid ]]; then
    echo "$old_uid $old_gid"
    return
  fi
  gid=${gid:-$uid}
  if ! uid=$(decimal "$uid") || ! gid=$(decimal "$gid"); then
    log "ignoring '${DEV_UID-}:${DEV_GID-}': expected decimal uid and gid up to 4294967294"
    echo "$old_uid $old_gid"
    return
  fi
  if ((uid == 0 || gid == 0)); then
    log "ignoring uid or gid 0"
    echo "$old_uid $old_gid"
    return
  fi
  owner=$(owner_name "$passwd_file" "$uid")
  if [[ -n $owner && $owner != "$user" ]]; then
    log "ignoring uid $uid: it belongs to '$owner'"
    echo "$old_uid $old_gid"
    return
  fi
  owner=$(owner_name "$group_file" "$gid")
  if [[ -n $owner && $owner != "$user" ]]; then
    log "keeping gid $old_gid: gid $gid belongs to group '$owner'"
    gid=$old_gid
  fi
  echo "$uid $gid"
}

# set_identity UID GID: gives `dev` this uid and gid, and its files on the
# home directory's own file system; mount points and mounted files below it
# belong to the host and are left alone. The files change first and passwd and
# group last, so that a start that fails in between is completed by the next.
set_identity() {
  local uid=$1 gid=$2 old_uid old_gid home_dev
  old_uid=$(field "$passwd_file" "$user" 3)
  old_gid=$(field "$passwd_file" "$user" 4)
  [[ $uid != "$old_uid" || $gid != "$old_gid" ]] || return 0
  home_dev=$(stat -c %d -- "$home")
  # Owner and group apart: a file of root in the group of dev stays root's.
  if ! own_files "-user" "$old_uid" "$uid" "$home_dev" ||
    ! own_files "-group" "$old_gid" ":$gid" "$home_dev"; then
    log "cannot give the files of '$user' under $home to $uid:$gid"
    return 1
  fi
  if ! sed -i -e "s/^$user:\([^:]*\):[0-9]*:[0-9]*:/$user:\1:$uid:$gid:/" "$passwd_file" ||
    ! sed -i -e "s/^$user:\([^:]*\):[0-9]*:/$user:\1:$gid:/" "$group_file" ||
    [[ $(field "$passwd_file" "$user" 3) != "$uid" || $(field "$group_file" "$user" 3) != "$gid" ]]; then
    log "cannot change '$user' to $uid:$gid in $passwd_file and $group_file"
    return 1
  fi
  log "user '$user' is now $uid:$gid"
}

# own_files TEST OLD NEW DEVICE: gives the files under home that match
# `find TEST OLD` and are on DEVICE to NEW. chown -h does not follow a link at
# the end of a path, but a process of dev that replaces a directory of the
# path with a link while the container starts could redirect it; chown -R
# would not, but it would also cross into mounted files of the host.
own_files() {
  find "$home" -xdev "$1" "$2" -printf '%D\0%p\0' |
    while IFS= read -r -d '' dev && IFS= read -r -d '' path; do
      if [[ $dev == "$4" ]]; then printf '%s\0' "$path"; fi
    done |
    change_owner "$3"
}

# give_streams UID GID: gives the pipes and sockets on stdin, stdout and stderr,
# such as the FIFOs of the container engine, to the user, so that it can
# reopen them as /dev/stdout and /dev/stderr after dropping root, as
# nix-direnv does. Files and terminals are left alone: they may belong to the
# host.
give_streams() {
  local fd target
  for fd in 0 1 2; do
    # The entrypoint's own descriptors: /proc/self would be those of readlink
    # and chown. Only anonymous pipes and sockets: a named FIFO may be a file
    # of the host.
    target=$(readlink "/proc/$$/fd/$fd" 2>/dev/null) || continue
    case $target in
      pipe:* | socket:*) chown "$1:$2" "/proc/$$/fd/$fd" 2>/dev/null || true ;;
    esac
  done
}

# supervise: runs the Nix daemon and restarts it when it exits; gives up after
# five exits in a row within a minute of their start.
supervise() {
  local failures=0 started
  while ((failures < 5)); do
    started=$SECONDS
    # Settings such as NIX_CONFIG in the container's environment must not
    # reach the daemon, which is root and trusts root (FY-0005).
    env -i PATH="$daemon_path" HOME=/root \
      NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
      nix-daemon >>"$daemon_log" 2>&1 || true
    if ((SECONDS - started >= 60)); then failures=0; fi
    failures=$((failures + 1))
    log "nix-daemon exited, restarting (see $daemon_log)"
    sleep 1
  done
  log "nix-daemon exited $failures times in a row, giving up"
}

# start_daemon: starts the supervised daemon and waits until it answers.
start_daemon() {
  if ! mkdir -p -- "$(dirname -- "$socket")" 2>/dev/null; then
    log "/nix is not writable: the Nix daemon is not started"
    return 0
  fi
  rm -f -- "$socket"
  if ! : >>"$daemon_log" 2>/dev/null; then
    log "cannot write $daemon_log; the Nix daemon logs to the container log"
    daemon_log=/proc/$$/fd/2
  fi
  supervise &
  local i
  for ((i = 0; i < daemon_wait; i++)); do
    if [[ -S $socket ]] && nix store info >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  log "the Nix daemon did not answer within $((daemon_wait / 10)) s (see $daemon_log)"
}

# runnable UID GID: the identity the command may run as: decimal, not root.
runnable() {
  decimal "$1" >/dev/null && decimal "$2" >/dev/null && (($1 != 0 && $2 != 0))
}

main() {
  if [[ $(id -u) != 0 ]]; then
    log "started as uid $(id -u) instead of 0: the Nix daemon is not running."
    log "start the container as root (the default); it switches to '$user' itself."
    exec "$@"
  fi
  local identity
  identity=$(wanted_identity)
  # shellcheck disable=SC2086 # two words: uid and gid
  set_identity $identity || exit 1
  start_daemon
  local uid gid
  uid=$(field "$passwd_file" "$user" 3)
  gid=$(field "$passwd_file" "$user" 4)
  # Never root: whatever passwd says, the command must run as dev.
  if ! runnable "$uid" "$gid"; then
    log "refusing to run the command as '$user' with uid $uid and gid $gid"
    exit 1
  fi
  give_streams "$uid" "$gid"
  # Resolved while PATH is still root's; then dev's PATH for the command.
  local tini setpriv
  tini=$(command -v tini)
  setpriv=$(command -v setpriv)
  export HOME=$home USER=$user LOGNAME=$user PATH=$dev_path
  exec "$tini" -s -g -- "$setpriv" --reuid="$uid" --regid="$gid" --init-groups -- "$@"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
