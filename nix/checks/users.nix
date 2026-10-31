# Every build user is in the build group; only root and dev have a shell.
{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.image) parts;
    in
    {
      checks.users = pkgs.runCommand "users" { inherit (parts.users) passwd group; } ''
        for name in ${toString parts.users.buildUsers}; do
          grep -q "^${parts.users.buildGroup}:.*[:,]$name\(,\|$\)" <<<"$group"
        done
        [[ $(grep -c ':/bin/bash$' <<<"$passwd") == 2 ]]
        touch $out
      '';
    };
}
