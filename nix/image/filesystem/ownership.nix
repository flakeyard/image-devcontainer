# Commands for the image root as fake root: dev owns its home directory.
{
  perSystem =
    { config, lib, ... }:
    let
      inherit (config.image.parts) users;
      home = users.homeRelative;
    in
    {
      options.image.filesystem.ownership = lib.mkOption {
        type = lib.types.lines;
        description = "Commands that set the owners and modes of the image files.";
      };
      config.image.filesystem.ownership = ''
        chown -R ${toString users.uid}:${toString users.uid} ${home}
        # Build users must not read the developer's files.
        chmod 750 ${home}
      '';
    };
}
