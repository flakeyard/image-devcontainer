# The entrypoint builds (writeShellApplication runs shellcheck), names the
# user and home of users.nix, and passes its unit tests.
{
  perSystem =
    { config, pkgs, ... }:
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
            unit = ../../tests/unit;
            built = parts.entrypoint;
          }
          ''
            grep -qx 'user=${parts.users.user}' "$script"
            grep -qx 'home=${parts.users.home}' "$script"
            shellcheck -x -e SC1091 "$unit/entrypoint.sh"
            PASSWD=$passwd GROUP=$group ENTRYPOINT=$script bash "$unit/entrypoint.sh"
            touch $out
          '';
    };
}
