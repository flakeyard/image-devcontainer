# The contents of the image: its tools, its roots, /bin/sh, /usr/bin/env and
# /usr/bin/bash.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image) parts roots dockerTools;
      # /usr/bin/bash, where GitHub-hosted runners have bash, so that scripts
      # written for them run here: the bash of /bin/bash and /bin/sh, not a
      # second one.
      usrBinBash = pkgs.runCommand "usr-bin-bash" { } ''
        mkdir -p $out/usr/bin
        ln -s ${lib.getExe' pkgs.bashInteractive "bash"} $out/usr/bin/bash
      '';
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
        usrBinBash
      ];
    };
}
