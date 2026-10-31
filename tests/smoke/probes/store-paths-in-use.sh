# shellcheck shell=sh
# Prints "missing PATH" for each store path that the files of the image, its
# links and CONFIG, the configuration of the image, name but the store lacks;
# then "checked".
store_path="/nix/store/[a-z0-9]{32}-[^/ \"':]+"
{
  grep -rhoE "$store_path" /etc /home/dev /usr/lib 2>/dev/null
  for link in /etc/ssl/certs/* /usr/lib/* /lib*/ld-linux*; do readlink "$link"; done
  printf '%s\n' "$CONFIG"
} | grep -oE "$store_path" | sort -u |
  while read -r path; do [ -e "$path" ] || echo "missing $path"; done
echo checked
