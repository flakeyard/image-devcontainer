# shellcheck shell=sh
# Sends SIGTERM to PID 1, tini, the moment its child, the entrypoint, execs
# the command as dev; first prints the name the child has then.
child=""
until [ -n "$child" ]; do
  child=$(cut -d ' ' -f 1 /proc/1/task/1/children 2>/dev/null)
done
while [ "$(cat "/proc/$child/comm" 2>/dev/null)" = entrypoint ]; do :; done
cat "/proc/$child/comm" 2>/dev/null || echo "an ended process"
kill -TERM 1
