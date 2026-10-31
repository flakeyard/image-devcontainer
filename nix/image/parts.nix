# The parts of the image by name, such as its Nix, tools, users and Nix
# settings. Each part is a module of this directory; everything that builds
# or checks the image takes them from here.
{
  perSystem =
    { lib, ... }:
    {
      options.image.parts = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        description = "The parts of the image by name.";
      };
    };
}
