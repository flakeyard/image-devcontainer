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

  # The scripts of the apps pass shellcheck and their unit tests.
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
        githubScripts = ../.github/scripts;
      }
      ''
        shellcheck "$scripts"/*.sh "$stubs"/* "$githubScripts"/*.sh
        shellcheck -x "$unit"/{lib,scripts,publish,release,licenses}.sh
        # The sandbox has no /usr/bin/env.
        cp -r "$scripts" scripts && cp -r "$stubs" stubs && cp -r "$githubScripts" github-scripts
        chmod -R u+w scripts stubs github-scripts
        patchShebangs scripts stubs github-scripts
        SCRIPTS=$PWD/scripts STUBS=$PWD/stubs bash "$unit/scripts.sh"
        SCRIPTS=$PWD/scripts STUBS=$PWD/stubs bash "$unit/publish.sh"
        SCRIPTS=$PWD/github-scripts STUBS=$PWD/stubs bash "$unit/release.sh"
        SCRIPTS=$PWD/scripts STUBS=$PWD/stubs bash "$unit/licenses.sh"
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
