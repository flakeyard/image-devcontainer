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

failed=0 passed=0 current=""

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
  change_owner() { tr '\0' '\n' >"$work/chowned"; }
  unset DEV_UID DEV_GID
}

report() {
  [[ -n $current ]] || return 0
  echo "FAIL $current: $1"
  failed=$((failed + 1))
  current=""
}

# identity NAME EXPECTED: runs wanted_identity in the working directory of the
# test; EXPECTED is "uid gid".
identity() {
  current=$1
  local out
  out=$(cd "$work/project" && wanted_identity 2>"$work/stderr")
  [[ $out == "$2" ]] || report "identity '$out', expected '$2'; $(cat "$work/stderr")"
}

message() {
  [[ -n $current ]] || return 0
  grep -qF -- "$1" "$work/stderr" || report "no message '$1' in: $(cat "$work/stderr")"
}

finish() {
  if [[ -n $current ]]; then passed=$((passed + 1)); fi
  current=""
  chmod -R u+rwx "$work" 2>/dev/null
  rm -rf -- "$work"
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

for value in abc -1 1e3 " 1001" "1001 " 12345678901; do
  setup
  export DEV_UID=$value
  identity "rejects DEV_UID='$value'" "1000 1000"
  message "expected decimal uid and gid"
  finish
done

setup
export DEV_UID=0
identity "rejects uid 0" "1000 1000"
message "ignoring uid or gid 0"
finish

setup
export DEV_UID=1001 DEV_GID=0
identity "rejects gid 0" "1000 1000"
message "ignoring uid or gid 0"
finish

setup
export DEV_UID=30001
identity "rejects the uid of a build user" "1000 1000"
message "ignoring uid 30001: it belongs to 'nixbld1'"
finish

setup
export DEV_UID=65534
identity "rejects the uid of nobody" "1000 1000"
message "it belongs to 'nobody'"
finish

setup
export DEV_UID=1001 DEV_GID=30000
identity "keeps the gid when it belongs to another group" "1001 1000"
message "keeping gid 1000: gid 30000 belongs to group 'nixbld'"
finish

setup
chmod 0 "$work/project"
current="reports an inaccessible working directory"
out=$(cd "$work/project" 2>/dev/null && wanted_identity 2>"$work/stderr")
# A directory without permissions cannot be entered: test from inside instead.
if [[ -z $out ]]; then
  chmod 700 "$work/project"
  out=$(cd "$work/project" && chmod 0 . && wanted_identity 2>"$work/stderr")
fi
[[ $out == "1000 1000" ]] || report "identity '$out'"
message "cannot inspect the working directory"
message "DAC_OVERRIDE"
finish

# --- set_identity -------------------------------------------------------------

setup
current="changes passwd, group and the files under home"
# The files of the test belong to the user running it: make that user `dev`.
sed -i "s/^dev:x:1000:1000:/dev:x:$(id -u):$(id -g):/" "$work/etc/passwd"
sed -i "s/^dev:x:1000:/dev:x:$(id -g):/" "$work/etc/group"
if set_identity 1002 1003 2>"$work/stderr"; then
  grep -qx "$work/home/.config/file" "$work/chowned" ||
    report "files given away: $(paste -sd' ' "$work/chowned")"
  [[ $(field "$work/etc/passwd" dev 3):$(field "$work/etc/passwd" dev 4) == 1002:1003 ]] ||
    report "passwd: $(grep '^dev:' "$work/etc/passwd")"
  [[ $(field "$work/etc/group" dev 3) == 1003 ]] || report "group: $(grep '^dev:' "$work/etc/group")"
else
  report "failed: $(cat "$work/stderr")"
fi
message "user 'dev' is now 1002:1003"
finish

setup
current="does nothing for the same identity"
set_identity 1000 1000 2>"$work/stderr" || report "failed"
[[ ! -e $work/chowned ]] || report "chown was called"
[[ ! -s $work/stderr ]] || report "message: $(cat "$work/stderr")"
finish

setup
current="reports an unwritable passwd file"
chmod 444 "$work/etc/passwd"
chmod 555 "$work/etc"
if set_identity 1002 1002 2>"$work/stderr"; then
  report "succeeded"
fi
chmod 755 "$work/etc"
message "cannot change 'dev' to 1002:1002"
finish

setup
current="reports a failing chown"
change_owner() { return 1; }
if set_identity 1002 1002 2>"$work/stderr"; then
  report "succeeded"
fi
message "cannot give the files of 'dev'"
finish

echo "passed: $passed, failed: $failed"
((failed == 0))
