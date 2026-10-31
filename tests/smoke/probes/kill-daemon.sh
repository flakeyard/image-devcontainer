# shellcheck shell=sh
# Kills the Nix daemon.
for process in /proc/[0-9]*; do
  [ "$(tr "\0" " " <"$process/cmdline" 2>/dev/null)" = "nix-daemon " ] && kill -9 "${process#/proc/}"
done
true
