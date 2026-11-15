# shellcheck shell=sh
# Prints the command lines in /proc that have PROBE_VALUE, from the start of
# the container until the entrypoint, the child of PID 1, has become the
# command, and once after.
handed_over() {
  child=$(cut -d ' ' -f 1 /proc/1/task/1/children 2>/dev/null)
  [ -n "${child}" ] || return 1
  comm=$(cat "/proc/${child}/comm" 2>/dev/null)
  [ "${comm}" != entrypoint ]
}

scan() {
  for cmdline in /proc/[0-9]*/cmdline; do
    # Processes may end while the loop reads /proc.
    words=$({ tr '\0' ' ' <"${cmdline}"; } 2>/dev/null)
    case ${words} in
      *"${PROBE_VALUE}"*) echo "${cmdline}" ;;
      # Command lines without the value are what the probe expects.
      *) ;;
    esac
  done
}

until handed_over; do scan; done
scan
echo scanned
