# The process of the container: it starts as root to run the Nix daemon,
# then switches to dev.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image.parts) entrypoint users;
    in
    {
      options.image.config.process = lib.mkOption {
        type = lib.types.raw;
        description = "The user, entrypoint, command and working directory of the image config.";
      };
      config.image.config.process = {
        User = "0:0";
        Entrypoint = [ (lib.getExe entrypoint) ];
        Cmd = [
          "${pkgs.coreutils}/bin/sleep"
          "infinity"
        ];
        WorkingDir = users.home;
      };
    };
}
