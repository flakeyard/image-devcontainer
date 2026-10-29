# Checks of the repository, run by `nix flake check` on every architecture.
{ pkgs }:
let
  inherit (pkgs) lib;
  parts = import ./parts.nix { inherit pkgs; };
  nixFiles = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ../.;
  };
in
{
  # Every tool builds, and its license allows redistribution.
  tools = pkgs.buildEnv {
    name = "image-tools";
    paths = parts.tools;
    ignoreCollisions = true;
  };

  # One Nix version: nix-direnv uses the image's Nix.
  nix-version = pkgs.runCommand "nix-version" { } ''
    grep -q "${parts.nix}" "${parts.nix-direnv}/share/nix-direnv/direnvrc"
    touch $out
  '';

  # Every build user is in the build group, and only dev has a login shell.
  users = pkgs.runCommand "users" { inherit (parts.users) passwd group; } ''
    for name in ${toString parts.users.buildUsers}; do
      grep -q "^${parts.users.buildGroup}:.*[:,]$name\(,\|$\)" <<<"$group"
    done
    [[ $(grep -c ':/bin/bash$' <<<"$passwd") == 2 ]]
    touch $out
  '';

  formatting =
    pkgs.runCommand "formatting"
      {
        nativeBuildInputs = [
          pkgs.nixfmt
          pkgs.diffutils
        ];
      }
      ''
        status=0
        for file in $(find ${nixFiles} -name '*.nix'); do
          if ! nixfmt --check "$file" 2>/dev/null; then
            diff -u "$file" <(nixfmt - <"$file") || true
            status=1
          fi
        done
        [[ $status == 0 ]] && touch $out
      '';
}
