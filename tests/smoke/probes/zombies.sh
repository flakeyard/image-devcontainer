# shellcheck shell=sh
# Prints the number of zombie processes, then the command line of PID 1.
zombies=0
for stat in /proc/[0-9]*/stat; do
  read -r _ _ state _ <"$stat" 2>/dev/null && [ "$state" = Z ] && zombies=$((zombies + 1))
done
echo "$zombies"
tr "\0" " " </proc/1/cmdline
