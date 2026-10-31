# Commands for the image root: its directories.
{
  perSystem =
    { config, lib, ... }:
    let
      home = config.image.parts.users.homeRelative;
    in
    {
      options.image.filesystem.directories = lib.mkOption {
        type = lib.types.lines;
        description = "Commands that make the directories of the image.";
      };
      config.image.filesystem.directories = ''
        mkdir -p etc/nix etc/ssl/certs tmp root var/empty var/log ${home}/.config/direnv
        chmod 1777 tmp
      '';
    };
}
