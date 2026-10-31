# Checks of the repository, run by `nix flake check` on every architecture.
{
  pkgs,
  parts,
  image,
}:
let
  inherit (pkgs) lib;
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

  # Every build user is in the build group; only root and dev have a shell.
  users = pkgs.runCommand "users" { inherit (parts.users) passwd group; } ''
    for name in ${toString parts.users.buildUsers}; do
      grep -q "^${parts.users.buildGroup}:.*[:,]$name\(,\|$\)" <<<"$group"
    done
    [[ $(grep -c ':/bin/bash$' <<<"$passwd") == 2 ]]
    touch $out
  '';

  # The entrypoint builds (writeShellApplication runs shellcheck), names the
  # user and home of users.nix, and passes its unit tests.
  entrypoint =
    pkgs.runCommand "entrypoint-tests"
      {
        nativeBuildInputs = with pkgs; [
          bash
          coreutils
          findutils
          gawk
          gnused
          gnugrep
          shellcheck
        ];
        inherit (parts.users) passwd group;
        script = ../entrypoint/entrypoint.sh;
        unit = ../tests/unit;
        built = parts.entrypoint;
      }
      ''
        grep -qx 'user=${parts.users.user}' "$script"
        grep -qx 'home=${parts.users.home}' "$script"
        shellcheck -x -e SC1091 "$unit/entrypoint.sh"
        PASSWD=$passwd GROUP=$group ENTRYPOINT=$script bash "$unit/entrypoint.sh"
        touch $out
      '';

  # The scripts of the apps and of .github pass shellcheck and their unit
  # tests, whose suites are at the paths of the scripts under tests/unit.
  scripts =
    pkgs.runCommand "script-tests"
      {
        nativeBuildInputs = with pkgs; [
          bash
          coreutils
          gawk
          git
          gnugrep
          jq
          shellcheck
        ];
        scripts = ../scripts;
        stubs = ../tests/bin;
        unit = ../tests/unit;
        # A store path name cannot start with a period.
        github = builtins.path {
          name = "github";
          path = ../.github;
        };
      }
      ''
        shellcheck "$scripts"/*.sh "$scripts"/*/*.sh "$stubs"/* "$github"/scripts/*.sh "$github"/actions/*/*.sh
        shellcheck -x "$unit"/lib.sh "$unit"/*/*.sh
        # The sandbox has no /usr/bin/env.
        cp -r "$scripts" scripts && cp -r "$stubs" stubs && cp -r "$github" github
        chmod -R u+w scripts stubs github
        patchShebangs scripts stubs github
        for suite in "$unit"/{check,publish}/*.sh; do
          SCRIPTS=$PWD/scripts STUBS=$PWD/stubs bash "$suite"
        done
        for suite in "$unit"/release/*.sh; do
          SCRIPTS=$PWD/github STUBS=$PWD/stubs bash "$suite"
        done
        touch $out
      '';

  # The image builds.
  inherit image;

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
