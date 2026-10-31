# shellcheck shell=sh
# Prints "wrote FILE" for each file that decides trust and that dev could
# write, the owner and mode of the store, then "checked".
for file in /etc/passwd /etc/group /etc/nix/nix.conf /etc/nix/new.conf /nix/var/nix/db/new /nix/var/nix/gcroots/new; do
  touch "$file" 2>/dev/null && echo "wrote $file"
done
stat -c "%U:%G %a" /nix/store
echo checked
