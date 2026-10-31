# Every tool builds, and its license allows redistribution.
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.tools = pkgs.buildEnv {
        name = "image-tools";
        paths = config.image.parts.tools;
        ignoreCollisions = true;
      };
    };
}
