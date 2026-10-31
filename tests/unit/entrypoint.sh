#!/usr/bin/env bash
# Unit tests of the entrypoint's identity logic, without root or docker: the
# entrypoint is sourced, and its files, mount check, owner lookup and chown are
# replaced by test doubles.
#
# Inputs (environment): ENTRYPOINT, the script; PASSWD and GROUP, the files of
# the image.
# shellcheck disable=SC2034,SC2329 # variables and functions of the sourced entrypoint
set -uo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# setup: a fresh copy of the image's users and a home directory.
setup() {
  work=$(mktemp -d)
  mkdir "$work/etc"
  printf '%s' "$PASSWD" >"$work/etc/passwd"
  printf '%s' "$GROUP" >"$work/etc/group"
  mkdir -p "$work/home/.config" "$work/project"
  touch "$work/home/.config/file"
  # shellcheck source-path=SCRIPTDIR source=../../entrypoint/entrypoint.sh
  source "$ENTRYPOINT"
  passwd_file=$work/etc/passwd group_file=$work/etc/group home=$work/home
  MOUNT="" OWNER="1000 1000"
  is_mount() { [[ -n $MOUNT ]]; }
  owner_of() { echo "$OWNER"; }
  change_owner() {
    echo "owner $1" >>"$work/chowned"
    tr '\0' '\n' >>"$work/chowned"
  }
  unset DEV_UID DEV_GID
}

# on_finish: makes the files of a test removable again.
on_finish() { chmod -R u+rwx "$work" 2>/dev/null; }

# in_project COMMAND...: runs COMMAND in the working directory of the test.
in_project() { (cd "$work/project" && "$@"); }

# identity NAME EXPECTED: runs wanted_identity in the working directory of the
# test; EXPECTED is "uid gid".
identity() {
  local name=$1 expected=$2
  run "$name" any in_project wanted_identity
  expect output "$expected"
}

# identity_in_locked_project: wanted_identity in a working directory without
# permissions. Root enters it as it is; another user cannot, so it enters
# first and takes the permissions away from inside.
identity_in_locked_project() {
  if (cd "$work/project" 2>/dev/null); then
    in_project wanted_identity
  else
    chmod 700 "$work/project"
    (cd "$work/project" && chmod 0 . && wanted_identity)
  fi
}

# --- wanted_identity ----------------------------------------------------------

setup
identity "no DEV_UID, not a mount point" "1000 1000"
finish

setup
MOUNT=1 OWNER="1002 1003"
identity "adopts the owner of a mounted working directory" "1002 1003"
finish

setup
MOUNT=1 OWNER="0 0"
identity "ignores a mount point owned by root" "1000 1000"
finish

setup
MOUNT="" OWNER="1002 1002"
identity "ignores a working directory that is not a mount point" "1000 1000"
finish

setup
export DEV_UID=1001
identity "DEV_UID alone sets the gid too" "1001 1001"
finish

setup
export DEV_UID=1001 DEV_GID=1005
identity "DEV_UID and DEV_GID" "1001 1005"
finish

setup
MOUNT=1 OWNER="1002 1002"
export DEV_UID=1001
identity "DEV_UID wins over the mount owner" "1001 1001"
finish

for value in 08 0100 01001; do
  setup
  export DEV_UID=$value
  identity "DEV_UID=$value is decimal" "$((10#$value)) $((10#$value))"
  finish
done

for value in abc -1 1e3 " 1001" "1001 " 12345678901 4294967295 4294967296 9999999999; do
  setup
  export DEV_UID=$value
  identity "rejects DEV_UID='$value'" "1000 1000"
  expect message "expected decimal uid and gid"
  finish
done

setup
export DEV_GID=1005
identity "DEV_GID without DEV_UID is ignored" "1000 1000"
finish

setup
MOUNT=1 OWNER="1002 0"
identity "a mount owned by group root is not adopted" "1000 1000"
expect message "ignoring uid or gid 0"
finish

setup
MOUNT=1 OWNER="30001 30000"
identity "a mount owned by a build user is not adopted" "1000 1000"
expect message "ignoring uid 30001: it belongs to 'nixbld1'"
finish

setup
export DEV_UID=0
identity "rejects uid 0" "1000 1000"
expect message "ignoring uid or gid 0"
finish

setup
export DEV_UID=1001 DEV_GID=0
identity "rejects gid 0" "1000 1000"
expect message "ignoring uid or gid 0"
finish

setup
export DEV_UID=30001
identity "rejects the uid of a build user" "1000 1000"
expect message "ignoring uid 30001: it belongs to 'nixbld1'"
finish

setup
export DEV_UID=65534
identity "rejects the uid of nobody" "1000 1000"
expect message "it belongs to 'nobody'"
finish

setup
export DEV_UID=1001 DEV_GID=30000
identity "keeps the gid when it belongs to another group" "1001 1000"
expect message "keeping gid 1000: gid 30000 belongs to group 'nixbld'"
finish

setup
chmod 0 "$work/project"
run "reports an inaccessible working directory" any identity_in_locked_project
expect output "1000 1000"
expect message "cannot inspect the working directory"
expect message "DAC_OVERRIDE"
finish

# --- set_identity -------------------------------------------------------------

setup
# The files of the test belong to the user running it: make that user `dev`.
sed -i "s/^dev:x:1000:1000:/dev:x:$(id -u):$(id -g):/" "$work/etc/passwd"
sed -i "s/^dev:x:1000:/dev:x:$(id -g):/" "$work/etc/group"
run "changes passwd, group and the files under home" ok set_identity 1002 1003
if still_passing; then
  [[ $(grep -A1 -x 'owner 1002' "$work/chowned" | tail -n +2) == *"$work/home"* ]] ||
    report "files not given to uid 1002: $(paste -sd' ' "$work/chowned")"
  grep -qx 'owner :1003' "$work/chowned" || report "group not changed apart: $(paste -sd' ' "$work/chowned")"
  grep -qx "$work/home/.config/file" "$work/chowned" ||
    report "files given away: $(paste -sd' ' "$work/chowned")"
  [[ $(field "$work/etc/passwd" dev 3):$(field "$work/etc/passwd" dev 4) == 1002:1003 ]] ||
    report "passwd: $(grep '^dev:' "$work/etc/passwd")"
  [[ $(field "$work/etc/group" dev 3) == 1003 ]] || report "group: $(grep '^dev:' "$work/etc/group")"
fi
expect message "user 'dev' is now 1002:1003"
finish

setup
run "does nothing for the same identity" ok set_identity 1000 1000
[[ ! -e $work/chowned ]] || report "chown was called"
expect empty "$work/err"
finish

setup
chmod 444 "$work/etc/passwd"
chmod 555 "$work/etc"
run "reports an unwritable passwd file" fail set_identity 1002 1002
chmod 755 "$work/etc"
expect message "cannot change 'dev' to 1002:1002"
finish

setup
change_owner() { return 1; }
run "a failing chown leaves passwd alone, and the next start completes" fail set_identity 1002 1002
expect message "cannot give the files of 'dev'"
[[ $(field "$work/etc/passwd" dev 3) == 1000 ]] || report "passwd changed: $(grep '^dev:' "$work/etc/passwd")"
change_owner() { cat >/dev/null; }
set_identity 1002 1002 >"$work/out" 2>"$work/err"
outcome ok $?
[[ $(field "$work/etc/passwd" dev 3) == 1002 ]] || report "passwd: $(grep '^dev:' "$work/etc/passwd")"
finish

setup
MOUNT=1
run "a mounted home keeps the owner of its files" ok set_identity 1002 1003
[[ ! -e $work/chowned ]] || report "files changed owner: $(paste -sd' ' "$work/chowned")"
[[ $(field "$work/etc/passwd" dev 3):$(field "$work/etc/group" dev 3) == 1002:1003 ]] ||
  report "passwd or group not changed"
expect message "$work/home is a mount point: its files keep their owner"
expect message "user 'dev' is now 1002:1003"
finish

setup
# The state after a start that changed passwd but failed on group.
sed -i 's/^dev:x:1000:1000:/dev:x:1002:1002:/' "$work/etc/passwd"
run "a group left behind by a failed start is completed" ok set_identity 1002 1002
[[ ! -e $work/chowned ]] || report "files changed owner again: $(paste -sd' ' "$work/chowned")"
[[ $(field "$work/etc/group" dev 3) == 1002 ]] || report "group: $(grep '^dev:' "$work/etc/group")"
expect message "user 'dev' is now 1002:1002"
finish

setup
chmod 444 "$work/etc/group"
chmod 555 "$work/etc"
run "a failing group change leaves passwd alone" fail set_identity 1002 1002
chmod 755 "$work/etc"
[[ $(field "$work/etc/passwd" dev 3) == 1000 ]] || report "passwd changed: $(grep '^dev:' "$work/etc/passwd")"
expect message "cannot change 'dev' to 1002:1002"
finish

setup
begin "keeps only the paths on the device of home"
out=$(printf '%s\0' 2049 /home/a 66 /home/mounted 2049 $'/home/new\nline' | paths_on 2049 | tr '\0' '|')
[[ $out == $'/home/a|/home/new\nline|' ]] || report "paths: $out"
finish

for identity in "0 1000" "1000 0" "4294967296 1000" "x 1000" "1000 1000"; do
  setup
  read -r uid gid <<<"$identity"
  begin "runnable $identity"
  if runnable "$uid" "$gid"; then result=yes; else result=no; fi
  expected=no
  [[ $identity == "1000 1000" ]] && expected=yes
  [[ $result == "$expected" ]] || report "runnable $identity is $result"
  finish
done

# --- supervise ----------------------------------------------------------------

setup
begin "root's PATH is fixed"
[[ $daemon_path == /bin:/usr/bin ]] || report "PATH of root without the build's tools: $daemon_path"
entrypoint_tools=/tools
# shellcheck source-path=SCRIPTDIR source=../../entrypoint/entrypoint.sh
source "$ENTRYPOINT"
unset entrypoint_tools
[[ $daemon_path == /tools:/bin:/usr/bin ]] || report "PATH of root with the build's tools: $daemon_path"
finish

setup
begin "root's Nix processes get proxies but not the container's settings"
daemon_path=$(dirname -- "$(command -v env)")
out=$(NIX_CONFIG='trusted-users = dev' NIX_USER_CONF_FILES=/tmp/nix.conf XDG_CONFIG_HOME=/tmp \
  https_proxy=http://proxy:3128 NO_PROXY=localhost no_proxy="" as_root NIX_REMOTE=daemon env)
expected="PATH=$daemon_path
HOME=/root
NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
https_proxy=http://proxy:3128
NO_PROXY=localhost
NIX_REMOTE=daemon"
[[ $out == "$expected" ]] || report "environment: $(paste -sd' ' <<<"$out")"
finish

setup
mkdir -p "$work/nix/daemon-socket"
chmod 555 "$work/nix/daemon-socket" "$work/nix"
socket=$work/nix/daemon-socket/socket
supervise() { touch "$work/supervised"; }
run "does not start the daemon when /nix is read-only" ok start_daemon
[[ ! -e $work/supervised ]] || report "the daemon was started"
expect message "/nix is not writable: the Nix daemon is not started"
finish

setup
mkdir "$work/bin"
printf '#!%s\necho started >>"%s/starts"; exit 1\n' "$(command -v bash)" "$work" >"$work/bin/nix-daemon"
chmod +x "$work/bin/nix-daemon"
daemon_path=$work/bin daemon_log=$work/daemon.log
sleep() { :; }
run "gives up after five quick exits of the daemon" any supervise
unset -f sleep
[[ $(wc -l <"$work/starts") == 5 ]] || report "started $(wc -l <"$work/starts") times"
expect message "nix-daemon exited 5 times in a row, giving up"
finish

summary
