# shellcheck shell=bash
# The image of this system as the apps that check, test and publish it build
# it with the Nix of the runner, sourced from $IMAGE_LIB.

# current_system: prints the system of the Nix of the runner, such as
# x86_64-linux.
current_system() {
  nix eval --raw --impure --expr builtins.currentSystem
}

# image_stream [FLAKE]: builds the image of this system from FLAKE, the
# current directory by default, and prints the script that streams it.
image_stream() {
  local flake=${1:-.}
  nix build --no-link --no-update-lock-file --print-out-paths "$flake#image"
}
