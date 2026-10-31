# shellcheck shell=sh
# Replaces the profile of dev by programs that only leave
# /tmp/ran-from-profile behind.
rm -rf "$HOME/.nix-profile" && mkdir -p "$HOME/.nix-profile/bin" &&
  for tool in sh bash direnv nix id; do
    printf "#!/bin/sh\ntouch /tmp/ran-from-profile\nexit 0\n" >"$HOME/.nix-profile/bin/$tool"
    chmod +x "$HOME/.nix-profile/bin/$tool"
  done
