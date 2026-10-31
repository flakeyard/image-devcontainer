# shellcheck shell=sh
# Prints the environment of the Nix daemon, one variable per line.
for process in /proc/[0-9]*; do
  [ "$(tr "\0" " " <"$process/cmdline" 2>/dev/null)" = "nix-daemon " ] && tr "\0" "\n" <"$process/environ"
done
true
