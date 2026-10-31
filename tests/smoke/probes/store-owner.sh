# shellcheck shell=sh
# Prints the owner and mode of the store, what dev could write of the store
# and the Nix settings, then "checked".
stat -c "%U %a" /nix/store
touch /nix/store/x 2>/dev/null && echo store-written
touch /etc/nix/local.conf 2>/dev/null && echo conf-written
echo checked
