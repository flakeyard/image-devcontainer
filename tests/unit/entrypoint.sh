#!/usr/bin/env bash
# Unit tests of the entrypoint's identity logic, without root or docker: the
# entrypoint is sourced, and its files, mount check, owner lookup and chown are
# replaced by test doubles. The harness is that of the shell library.
#
# The built entrypoint also runs as the image starts it, through environ, as a
# user other than root.
#
# Inputs (environment): ENTRYPOINT, the script; BUILT, the built entrypoint;
# ENVIRON, the built environ; PASSWD and GROUP, the files of the image;
# SHELL_LIB, the shell library.
# shellcheck disable=SC2034,SC2154,SC2329 # variables and functions of the sourced entrypoint
set -uo pipefail
export LC_ALL=C

testing=${SHELL_LIB:?the tests need SHELL_LIB, the directory of the shell library}/internal/testing
# shellcheck source=/dev/null
source "${testing}/case.sh"
# shellcheck source=/dev/null
source "${testing}/checks.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/checks.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/checks.sh"

# entrypoint_setup: setup of the library, a fresh copy of the image's users
# and a home directory.
entrypoint_setup() {
  setup
  mkdir "${work}/etc"
  printf '%s' "${PASSWD}" >"${work}/etc/passwd"
  printf '%s' "${GROUP}" >"${work}/etc/group"
  mkdir -p "${work}/home/.config" "${work}/project"
  touch "${work}/home/.config/file"
  # shellcheck source-path=SCRIPTDIR source=../../entrypoint/entrypoint.sh
  source "${ENTRYPOINT}"
  passwd_file=${work}/etc/passwd group_file=${work}/etc/group home=${work}/home
  mountinfo=${work}/mountinfo
  : >"${mountinfo}"
  MOUNT="" OWNER="1000 1000"
  is_mount() { [[ -n ${MOUNT} ]]; }
  owner_of() { echo "${OWNER}"; }
  change_owner() {
    echo "owner $1" >>"${work}/chowned"
    tr '\0' '\n' >>"${work}/chowned"
  }
}

# expect_field FILE N VALUE: field N of the entry of dev in the passwd or
# group FILE is VALUE.
expect_field() {
  local file=$1 n=$2 value=$3 actual entry
  [[ -n ${current} ]] || return 0
  actual=$(field "${file}" dev "${n}")
  [[ ${actual} != "${value}" ]] || return 0
  entry=$(grep '^dev:' "${file}")
  report "${file##*/}: ${entry}, expected field ${n} ${value}"
}

# The user running the tests, who owns their files.
test_uid=$(id -u)
test_gid=$(id -g)

# in_project COMMAND...: runs COMMAND in the working directory of the test.
in_project() { (cd "${work}/project" && "$@"); }

# identity NAME EXPECTED: runs wanted_identity in the working directory of the
# test; EXPECTED is "uid gid".
identity() {
  local name=$1 expected=$2
  run_lib "${name}" ok "" in_project wanted_identity
  expect stdout "${expected}"
}

# identity_in_locked_project: wanted_identity in a working directory without
# permissions. Root enters it as it is; another user cannot, so it enters
# first and takes the permissions away from inside.
identity_in_locked_project() {
  if (cd "${work}/project" 2>/dev/null); then
    in_project wanted_identity
  else
    chmod 700 "${work}/project"
    (cd "${work}/project" && chmod 0 . && wanted_identity)
  fi
}

# --- wanted_identity ----------------------------------------------------------

entrypoint_setup
identity "no DEV_UID, not a mount point" "1000 1000"
finish

entrypoint_setup
MOUNT=1 OWNER="1002 1003"
identity "adopts the owner of a mounted working directory" "1002 1003"
finish

entrypoint_setup
MOUNT=1 OWNER="0 0"
identity "ignores a mount point owned by root" "1000 1000"
finish

entrypoint_setup
MOUNT="" OWNER="1002 1002"
identity "ignores a working directory that is not a mount point" "1000 1000"
finish

entrypoint_setup
apply DEV_UID=1001
identity "DEV_UID alone sets the gid too" "1001 1001"
finish

entrypoint_setup
apply DEV_UID=1001 DEV_GID=1005
identity "DEV_UID and DEV_GID" "1001 1005"
finish

entrypoint_setup
MOUNT=1 OWNER="1002 1002"
apply DEV_UID=1001
identity "DEV_UID wins over the mount owner" "1001 1001"
finish

for value in 08 0100 01001; do
  entrypoint_setup
  apply DEV_UID="${value}"
  identity "DEV_UID=${value} is decimal" "$((10#${value})) $((10#${value}))"
  finish
done

for value in abc -1 1e3 " 1001" "1001 " 12345678901 4294967295 4294967296 9999999999; do
  entrypoint_setup
  apply DEV_UID="${value}"
  identity "rejects DEV_UID='${value}'" "1000 1000"
  expect message "expected decimal uid and gid"
  finish
done

entrypoint_setup
apply DEV_GID=1005
identity "DEV_GID without DEV_UID is ignored" "1000 1000"
finish

entrypoint_setup
MOUNT=1 OWNER="1002 0"
identity "a mount owned by group root is not adopted" "1000 1000"
expect message "ignoring uid or gid 0"
finish

entrypoint_setup
MOUNT=1 OWNER="30001 30000"
identity "a mount owned by a build user is not adopted" "1000 1000"
expect message "ignoring uid 30001: it belongs to 'nixbld1'"
finish

entrypoint_setup
apply DEV_UID=0
identity "rejects uid 0" "1000 1000"
expect message "ignoring uid or gid 0"
finish

entrypoint_setup
apply DEV_UID=1001 DEV_GID=0
identity "rejects gid 0" "1000 1000"
expect message "ignoring uid or gid 0"
finish

entrypoint_setup
apply DEV_UID=30001
identity "rejects the uid of a build user" "1000 1000"
expect message "ignoring uid 30001: it belongs to 'nixbld1'"
finish

entrypoint_setup
apply DEV_UID=65534
identity "rejects the uid of nobody" "1000 1000"
expect message "it belongs to 'nobody'"
finish

entrypoint_setup
apply DEV_UID=1001 DEV_GID=30000
identity "keeps the gid when it belongs to another group" "1001 1000"
expect message "keeping gid 1000: gid 30000 belongs to group 'nixbld'"
finish

entrypoint_setup
chmod 0 "${work}/project"
run_lib "reports an inaccessible working directory" ok "" identity_in_locked_project
expect stdout "1000 1000"
expect message "cannot inspect the working directory"
expect message "DAC_OVERRIDE"
finish

# --- set_identity -------------------------------------------------------------

entrypoint_setup
# The files of the test belong to the user running it: make that user `dev`.
sed -i "s/^dev:x:1000:1000:/dev:x:${test_uid}:${test_gid}:/" "${work}/etc/passwd"
sed -i "s/^dev:x:1000:/dev:x:${test_gid}:/" "${work}/etc/group"
run_lib "changes passwd, group and the files under home" ok "" set_identity 1002 1003
if [[ -n ${current} ]]; then
  given=$(grep -A1 -x 'owner 1002' "${work}/chowned")
  [[ ${given} == *"${work}/home"* ]] \
    || report "files not given to uid 1002: $(<"${work}/chowned")"
  grep -qx 'owner :1003' "${work}/chowned" || report "group not changed apart: $(<"${work}/chowned")"
  grep -qx "${work}/home/.config/file" "${work}/chowned" \
    || report "files given away: $(<"${work}/chowned")"
fi
expect_field "${work}/etc/passwd" 3 1002
expect_field "${work}/etc/passwd" 4 1003
expect_field "${work}/etc/group" 3 1003
expect message "user 'dev' is now 1002:1003"
finish

entrypoint_setup
run_lib "does nothing for the same identity" ok "" set_identity 1000 1000
[[ ! -e ${work}/chowned ]] || report "chown was called"
[[ -z ${current} || ! -s ${work}/stderr ]] || report "stderr: $(<"${work}/stderr")"
finish

entrypoint_setup
chmod 444 "${work}/etc/passwd"
chmod 555 "${work}/etc"
run_lib "reports an unwritable passwd file" fail "" set_identity 1002 1002
chmod 755 "${work}/etc"
expect message "cannot change 'dev' to 1002:1002"
finish

entrypoint_setup
change_owner() { return 1; }
run_lib "a failing chown leaves passwd alone, and the next start completes" fail "" set_identity 1002 1002
expect message "cannot give the files of 'dev'"
expect_field "${work}/etc/passwd" 3 1000
change_owner() { cat >/dev/null; }
run_lib "a failing chown leaves passwd alone, and the next start completes" ok "" set_identity 1002 1002
expect_field "${work}/etc/passwd" 3 1002
finish

entrypoint_setup
MOUNT=1
run_lib "a mounted home keeps the owner of its files" ok "" set_identity 1002 1003
[[ ! -e ${work}/chowned ]] || report "files changed owner: $(<"${work}/chowned")"
expect_field "${work}/etc/passwd" 3 1002
expect_field "${work}/etc/group" 3 1003
expect message "${work}/home is a mount point: its files keep their owner"
expect message "user 'dev' is now 1002:1003"
finish

entrypoint_setup
# The state after a start that changed passwd but failed on group.
sed -i 's/^dev:x:1000:1000:/dev:x:1002:1002:/' "${work}/etc/passwd"
run_lib "a group left behind by a failed start is completed" ok "" set_identity 1002 1002
[[ ! -e ${work}/chowned ]] || report "files changed owner again: $(<"${work}/chowned")"
expect_field "${work}/etc/group" 3 1002
expect message "user 'dev' is now 1002:1002"
finish

entrypoint_setup
chmod 444 "${work}/etc/group"
chmod 555 "${work}/etc"
run_lib "a failing group change leaves passwd alone" fail "" set_identity 1002 1002
chmod 755 "${work}/etc"
expect_field "${work}/etc/passwd" 3 1000
expect message "cannot change 'dev' to 1002:1002"
finish

# mounted PATH: a line of mountinfo for a mount point at PATH, escaped.
mounted() {
  local path=$1
  path=${path//\\/\\134} path=${path// /\\040} path=${path//$'\t'/\\011} path=${path//$'\n'/\\012}
  printf '36 35 0:40 / %s rw,relatime - ext4 /dev/sda1 rw\n' "${path}"
}

entrypoint_setup
current="leaves out the mount points under home"
for path in "${home}/mounted dir" "${home}/new"$'\n'"line" "${home}/back\\slash" /elsewhere; do
  mounted "${path}" >>"${mountinfo}"
done
out=$(printf '%s\0' "${home}/a" "${home}/mounted dir" "${home}/new"$'\n'"line" "${home}/back\\slash" "${home}/b" | not_mounted | tr '\0' '|')
[[ ${out} == "${home}/a|${home}/b|" ]] || report "paths: ${out}"
finish

# Files of the image layers on overlayfs may have another device than home.
entrypoint_setup
sed -i "s/^dev:x:1000:1000:/dev:x:${test_uid}:${test_gid}:/" "${work}/etc/passwd"
sed -i "s/^dev:x:1000:/dev:x:${test_gid}:/" "${work}/etc/group"
mkdir "${work}/home/project"
touch "${work}/home/.gitconfig"
mounted "${work}/home/project" >"${mountinfo}"
mounted "${work}/home/.gitconfig" >>"${mountinfo}"
run_lib "gives the files under home to dev, but not mount points" ok "" set_identity 1002 1003
if [[ -n ${current} ]]; then
  grep -qx "${work}/home/.config/file" "${work}/chowned" || report "files not given: $(<"${work}/chowned")"
  ! grep -qx -e "${work}/home/project" -e "${work}/home/.gitconfig" "${work}/chowned" \
    || report "mount points given away: $(<"${work}/chowned")"
fi
finish

entrypoint_setup
mountinfo=${work}/missing
run_lib "keeps the files when the mount points are unknown" fail "" set_identity 1002 1002
expect message "cannot give the files of 'dev'"
[[ ! -s ${work}/chowned ]] || report "files changed owner: $(<"${work}/chowned")"
finish

# A failing read of mountinfo used to leave every path in, mount points too.
entrypoint_setup
current="not_mounted fails when it cannot read mountinfo"
mountinfo=${work}/missing
out=$(printf '%s\0' "${home}/a" | not_mounted 2>/dev/null)
status=$?
[[ ${status} != 0 && -z ${out} ]] || report "status ${status}, paths: ${out}"
finish

entrypoint_setup
not_mounted() {
  cat >/dev/null
  return 2
}
run_lib "keeps the files when the mount points cannot be read" fail "" set_identity 1002 1002
expect message "cannot give the files of 'dev'"
expect_field "${work}/etc/passwd" 3 1000
# The double of change_owner records the owner before it reads any path.
! grep -qv '^owner ' "${work}/chowned" 2>/dev/null || report "files changed owner: $(<"${work}/chowned")"
finish

for identity in "0 1000" "1000 0" "4294967296 1000" "x 1000" "1000 1000"; do
  entrypoint_setup
  read -r uid gid <<<"${identity}"
  current="runnable ${identity}"
  if runnable "${uid}" "${gid}"; then result=yes; else result=no; fi
  expected=no
  [[ ${identity} == "1000 1000" ]] && expected=yes
  [[ ${result} == "${expected}" ]] || report "runnable ${identity} is ${result}"
  finish
done

# --- the environment of the container -----------------------------------------

# read_settings ENTRY...: passes the ENTRYs, each ended by a NUL, to
# read_environment through a descriptor, as environ does; prints the settings
# it sets, the variable NIX_CONFIG, and the number of variables it keeps.
read_settings() {
  local fd
  printf '%s\0' "$@" >"${work}/environment"
  exec {fd}<"${work}/environment"
  read_environment "${fd}" sleep || return
  printf '%s\n' "${DEV_UID-unset}" "${DEV_GID-unset}" "${https_proxy-unset}" "${NIX_CONFIG-unset}" \
    "${#container_environment[@]}"
}

entrypoint_setup
run_lib "sets the settings of the container's variables, and keeps all" ok "" read_settings \
  DEV_UID=1001 https_proxy=http://proxy:3128 NIX_CONFIG=x DEV_GID ""
expect stdout "$(printf '%s\n' 1001 unset http://proxy:3128 unset 5)"
finish

# Not a number, a standard stream, too large, nothing, a closed descriptor,
# and no command.
for arguments in "sleep infinity" "1 sleep" "0 sleep" "99999999999999999999 sleep" "" "99 sleep" "99"; do
  entrypoint_setup
  # shellcheck disable=SC2086 # the words of the case
  run_lib "rejects the arguments '${arguments}'" fail "" read_environment ${arguments}
  expect message "expected the descriptor of the variables of the container, and the command"
  finish
done

# --- supervise ----------------------------------------------------------------

entrypoint_setup
current="root's PATH is fixed"
[[ ${daemon_path} == /bin:/usr/bin ]] || report "PATH of root without the build's tools: ${daemon_path}"
entrypoint_tools=/tools
# shellcheck source-path=SCRIPTDIR source=../../entrypoint/entrypoint.sh
source "${ENTRYPOINT}"
unset entrypoint_tools
[[ ${daemon_path} == /tools:/bin:/usr/bin ]] || report "PATH of root with the build's tools: ${daemon_path}"
finish

entrypoint_setup
current="root's Nix processes get proxies but not the container's settings"
env_path=$(command -v env)
daemon_path=$(dirname -- "${env_path}")
out=$(NIX_CONFIG='trusted-users = dev' NIX_USER_CONF_FILES=/tmp/nix.conf XDG_CONFIG_HOME=/tmp \
  https_proxy=http://proxy:3128 NO_PROXY=localhost no_proxy="" as_root NIX_REMOTE=daemon env)
expected="PATH=${daemon_path}
HOME=/root
NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
https_proxy=http://proxy:3128
NO_PROXY=localhost
NIX_REMOTE=daemon"
[[ ${out} == "${expected}" ]] || report "environment: ${out//$'\n'/ }"
finish

entrypoint_setup
mkdir -p "${work}/nix/daemon-socket"
chmod 555 "${work}/nix/daemon-socket" "${work}/nix"
socket=${work}/nix/daemon-socket/socket
supervise() { touch "${work}/supervised"; }
run_lib "does not start the daemon when /nix is read-only" ok "" start_daemon
[[ ! -e ${work}/supervised ]] || report "the daemon was started"
expect message "/nix is not writable: the Nix daemon is not started"
# finish removes the files of the test.
chmod -R u+w "${work}/nix"
finish

entrypoint_setup
mkdir "${work}/bin"
bash_path=$(command -v bash)
printf '#!%s\necho started >>"%s/starts"; exit 1\n' "${bash_path}" "${work}" >"${work}/bin/nix-daemon"
chmod +x "${work}/bin/nix-daemon"
daemon_path=${work}/bin daemon_log=${work}/daemon.log
sleep() { :; }
run_lib "gives up after five quick exits of the daemon" ok "" supervise
unset -f sleep
starts=$(wc -l <"${work}/starts")
[[ ${starts} == 5 ]] || report "started ${starts} times"
expect message "nix-daemon exited 5 times in a row, giving up"
finish

entrypoint_setup
daemon_log_max_bytes=10
printf '%s\n' first-line >"${work}/daemon.log"
run_lib "moves a full daemon log aside" ok "" append_bounded "${work}/daemon.log" <<<"second-line"
expect_line "${work}/daemon.log.old" first-line
expect_line "${work}/daemon.log" second-line
if [[ -n ${current} ]] && grep -q first-line "${work}/daemon.log"; then report "the old lines stayed"; fi
finish

entrypoint_setup
run_lib "appends to a daemon log below its size" ok "" append_bounded "${work}/daemon.log" <<<$'one\ntwo'
expect_line "${work}/daemon.log" one
expect_line "${work}/daemon.log" two
[[ ! -e ${work}/daemon.log.old ]] || report "the log moved aside"
finish

entrypoint_setup
daemon_log_max_bytes=0
run_lib "passes the daemon log through when it is not a regular file" ok "" append_bounded /dev/stdout <<<"to-the-container"
expect stdout "to-the-container"
finish

# --- the built entrypoint -----------------------------------------------------

# The tests run it as a user other than root, as the build does, so that it
# takes no root actions; the image starts it through environ.
code_root=${ENVIRON:?the tests need ENVIRON, the built environ}
# A library that does not exist: glibc reports it for every program that
# reads LD_PRELOAD, here the command alone.
missing_library=/no-such-library.so

# The environment of the container must not change root's bash: bash would
# source BASH_ENV, import the exported function id, which tells the
# entrypoint it is root, and trace with SHELLOPTS.
if ((test_uid != 0)); then
  entrypoint_setup
  printf 'touch %q\n' "${work}/sourced" >"${work}/bash-env"
  run "the container's environment does not reach root's bash" ok bin/environ \
    BASH_ENV="${work}/bash-env" 'BASH_FUNC_id%%=() { echo 0; }' SHELLOPTS=xtrace \
    -- to-fd "${BUILT}/bin/entrypoint" printf '%s\n' ran
  expect stdout ran
  expect message "started as uid ${test_uid} instead of 0"
  [[ ! -e ${work}/sourced ]] || report "bash sourced BASH_ENV"
  ! grep -q '^+' "${work}/stderr" || report "bash traced: $(<"${work}/stderr")"
  finish

  entrypoint_setup
  run "only the command reads LD_PRELOAD, and gets the container's variables" ok bin/environ \
    LD_PRELOAD="${missing_library}" GCONV_PATH=/tmp -- to-fd "${BUILT}/bin/entrypoint" env
  expect_line "${work}/stdout" "LD_PRELOAD=${missing_library}"
  expect_line "${work}/stdout" GCONV_PATH=/tmp
  readers=$(grep -c "${missing_library}" "${work}/stderr")
  [[ ${readers} == 1 ]] \
    || report "programs that read LD_PRELOAD: $(<"${work}/stderr")"
  finish
fi

conclude
