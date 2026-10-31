# The dockerTools that build the image: the image's Nix writes the store
# database of the image.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.image.dockerTools = lib.mkOption {
        type = lib.types.raw;
        description = "The dockerTools that build the image.";
      };
      config.image.dockerTools = pkgs.dockerTools.override { inherit (config.image.parts) nix; };
    };
}
