# Commands for the image root: its directories.
{
  perSystem =
    { config, lib, ... }:
    let
      home = config.image.parts.users.homeRelative;
      # The targets of named volumes that the README names. Docker and Podman
      # copy the owner of a directory of the image into a new volume; a
      # directory the image lacks becomes a volume of root.
      volumeTargets = [
        ".cache"
        ".local/share"
        ".vscode-server"
      ];
    in
    {
      options.image.filesystem.directories = lib.mkOption {
        type = lib.types.lines;
        description = "Commands that make the directories of the image.";
      };
      config.image.filesystem.directories = ''
        mkdir -p etc/nix etc/ssl/certs tmp root var/empty var/log ${home}/.config/direnv
        mkdir -p ${lib.concatMapStringsSep " " (target: "${home}/${target}") volumeTargets}
        chmod 1777 tmp
      '';
    };
}
