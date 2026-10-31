# shellcheck shell=sh
# Prints the uid of the command of the container, sleep infinity. Its first
# word is sleep itself; the entrypoint and tini only end with it.
for process in /proc/[0-9]*; do
  # shellcheck disable=SC2046 # the words of the command line
  set -- $(cat "$process/cmdline" 2>/dev/null | tr "\0" " ")
  [ "${1##*/}" = sleep ] && [ "${2-}" = infinity ] && awk '/^Uid:/ { print $2 }' "$process/status" 2>/dev/null
done
