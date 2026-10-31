# The image, from the files that are not flake-parts modules yet.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image) parts;
    in
    {
      options.image.parts = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        description = "The parts of the image, such as its Nix, tools and users.";
      };

      config = {
        image.parts = import ./_parts.nix { inherit pkgs; };

        # The image as a script that streams a docker archive to stdout.
        packages.image = import ./_image.nix { inherit pkgs parts; };
      };
    };
}
