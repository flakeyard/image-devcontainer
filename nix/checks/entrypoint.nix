# The entrypoint builds (writeShellApplication runs shellcheck), names the
# user and home of nix/image/parts/users.nix, and passes its unit tests and
# those of environ, with the harness of the shell library that test.yaml pins.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      root,
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
            inherit (parts) environ;
            script = root + "/entrypoint/entrypoint.sh";
            tests = lib.fileset.toSource {
              root = root + "/tests";
              fileset = lib.fileset.unions [
                (root + "/tests/lib/checks.sh")
                (root + "/tests/unit/entrypoint.sh")
                (root + "/tests/unit/environ.sh")
              ];
            };
            built = parts.entrypoint;
          }
          ''
            grep -qx 'user=${parts.users.user}' "$script"
            grep -qx 'home=${parts.users.home}' "$script"
            shellcheck -x -e SC1091 "$tests/unit/entrypoint.sh" "$tests/unit/environ.sh"
            PASSWD=$passwd GROUP=$group ENTRYPOINT=$script BUILT=$built ENVIRON=$environ SHELL_LIB=${shellLib} \
              bash "$tests/unit/entrypoint.sh"
            ENVIRON=$environ SHELL_LIB=${shellLib} bash "$tests/unit/environ.sh"
            touch $out
          '';
    };
}
