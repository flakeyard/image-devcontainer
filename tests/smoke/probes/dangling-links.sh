# shellcheck shell=sh
# Prints "dangling LINK" for each link into the store, outside the store,
# whose target is gone; then "checked".
find / -xdev -path /nix/store -prune -o -type l -lname "/nix/store/*" -print |
  while read -r link; do [ -e "$link" ] || echo "dangling $link"; done
echo checked
