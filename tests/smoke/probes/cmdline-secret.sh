# shellcheck shell=sh
# Prints the command lines in /proc that have PROBE_VALUE, from the start of
# the container until the entrypoint, the child of PID 1, has become the
# command, and once after.
handed_over() {
  child=$(cut -d ' ' -f 1 /proc/1/task/1/children 2>/dev/null)
  [ -n "$child" ] && [ "$(cat "/proc/$child/comm" 2>/dev/null)" != entrypoint ]
}

scan() {
  for cmdline in /proc/[0-9]*/cmdline; do
    # Processes may end while the loop reads /proc.
    case $({ tr '\0' ' ' <"$cmdline"; } 2>/dev/null) in
      *"$PROBE_VALUE"*) echo "$cmdline" ;;
    esac
  done
}

until handed_over; do scan; done
scan
echo scanned
