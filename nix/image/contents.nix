# The contents of the image: its tools, its roots, /bin/sh and /usr/bin/env.
{
  perSystem =
    { config, lib, ... }:
    let
      inherit (config.image) parts roots dockerTools;
    in
    {
      options.image.contents = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        description = "The store paths the image contains, in order.";
      };
      config.image.contents = parts.tools ++ [
        roots
        dockerTools.binSh
        dockerTools.usrBinEnv
      ];
    };
}
