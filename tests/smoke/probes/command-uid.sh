# shellcheck shell=sh
# Prints the uid of the command of the container, sleep infinity. Its first
# word is sleep itself; the entrypoint only becomes it.
for process in /proc/[0-9]*; do
  words=$({ tr "\0" " " <"${process}/cmdline"; } 2>/dev/null)
  # shellcheck disable=SC2086 # the words of the command line
  set -- ${words}
  [ "${1##*/}" = sleep ] && [ "${2-}" = infinity ] && awk '/^Uid:/ { print $2 }' "${process}/status" 2>/dev/null
done
