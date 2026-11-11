# The entrypoint builds (writeShellApplication runs shellcheck), names the
# user and home of nix/image/parts/users.nix, and passes its unit tests, with
# the harness of the shell library that test.yaml pins.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      shellLib,
      ...
    }:
    let
      inherit (config.image) parts;
    in
    {
      checks.entrypoint =
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
            script = ../../entrypoint/entrypoint.sh;
            tests = lib.fileset.toSource {
              root = ../../tests;
              fileset = lib.fileset.unions [
                ../../tests/lib/checks.sh
                ../../tests/unit/entrypoint.sh
              ];
            };
            built = parts.entrypoint;
          }
          ''
            grep -qx 'user=${parts.users.user}' "$script"
            grep -qx 'home=${parts.users.home}' "$script"
            shellcheck -x -e SC1091 "$tests/unit/entrypoint.sh"
            PASSWD=$passwd GROUP=$group ENTRYPOINT=$script BUILT=$built SHELL_LIB=${shellLib} \
              bash "$tests/unit/entrypoint.sh"
            touch $out
          '';
    };
}
