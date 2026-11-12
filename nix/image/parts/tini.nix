# tini, the first program of the image, linked statically: no dynamic loader
# runs before it and reads LD_PRELOAD and the like from the environment of
# the container.
{
  perSystem =
    { pkgs, ... }:
    {
      image.parts.tini = pkgs.pkgsStatic.tini;
    };
}
