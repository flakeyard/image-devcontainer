# Commands for the image root: the files of dev's home directory. direnv
# loads nix-direnv.
{
  perSystem =
    { config, lib, ... }:
    let
      inherit (config.image.parts) users nix-direnv;
      home = users.homeRelative;
    in
    {
      options.image.filesystem.home = lib.mkOption {
        type = lib.types.lines;
        description = "Commands that write the files of dev's home directory.";
      };
      config.image.filesystem.home = ''
        echo 'source ${nix-direnv}/share/nix-direnv/direnvrc' > ${home}/.config/direnv/direnvrc
      '';
    };
}
