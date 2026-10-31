# The image builds.
{
  perSystem =
    { config, ... }:
    {
      checks.image = config.packages.image;
    };
}
